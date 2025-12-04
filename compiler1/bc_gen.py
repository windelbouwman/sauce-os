"""Generate bytecode from AST."""

import logging
from dataclasses import dataclass
from . import ast
from . import bc
from .bc import OpCode

logger = logging.getLogger("slangc.bytecode-gen")


def gen_bc(modules: list[ast.Module]) -> bc.Program:
    logger.info("generating bytecode")
    g = ByteCodeGenerator()
    g.gen_modules(modules)

    return bc.Program(g._types, g._globals, g._functions)


@dataclass
class LoopBlock:
    start_label: int
    final_label: int


@dataclass
class TryBlock:
    pass


class ByteCodeGenerator:
    def __init__(self):
        self._counter = 0
        self._loops = []
        self._functions = []
        self._globals = []
        self._types = []
        self._code = []
        self._locals = []
        self._label_map = {}
        self._type_map = {}

        self._binop_map = {
            "+": OpCode.ADD,
            "-": OpCode.SUB,
            "*": OpCode.MUL,
            "/": OpCode.DIV,
            "<": OpCode.LT,
            ">": OpCode.GT,
            "<=": OpCode.LTE,
            ">=": OpCode.GTE,
            "==": OpCode.EQ,
            "and": OpCode.AND,
            "or": OpCode.OR,
            "&": OpCode.BITAND,
            "|": OpCode.BITOR,
            "^": OpCode.BITXOR,
            "<<": OpCode.BITSHL,
            ">>": OpCode.BITSHR,
        }

        self._unop_map = {
            "not": OpCode.NOT,
            "-": OpCode.NEG,
        }

    def gen_modules(self, modules: list[ast.Module]):
        for module in modules:
            self.gen_module(module)

    def gen_module(self, module: ast.Module):
        # Forward declare types:
        cnt = 0
        for definition in module.definitions:
            if isinstance(definition, ast.StructDef):
                self._type_map[id(definition)] = cnt
                cnt += 1
            elif isinstance(definition, ast.VarDef):
                global_index = len(self._globals)
                self._code = []
                self.gen_expression(definition.value)
                self._globals.append(self._code)
                self._type_map[id(definition)] = global_index

        for definition in module.definitions:
            if isinstance(definition, ast.FunctionDef):
                self.gen_function(definition)
            elif isinstance(definition, ast.StructDef):
                self.gen_struct(definition)
            elif isinstance(definition, ast.ExternFunction):
                # TODO: maybe generate import clause?
                pass
            elif isinstance(definition, ast.VarDef):
                pass
            else:
                raise NotImplementedError(str(definition))

    def get_bc_ty(self, ty: ast.Type) -> bc.Typ:
        if ty.is_int():
            return bc.BaseTyp(bc.SimpleTyp.INT)
        elif ty.is_str():
            return bc.BaseTyp(bc.SimpleTyp.STR)
        elif ty.is_float():
            return bc.BaseTyp(bc.SimpleTyp.FLOAT)
        elif ty.is_bool():
            return bc.BaseTyp(bc.SimpleTyp.BOOL)
        elif ty.is_char():
            return bc.BaseTyp(bc.SimpleTyp.CHAR)
        elif ty.is_struct():
            return bc.StructTyp(self._type_map[id(ty.kind.tycon)])
        elif ty.is_function():
            param_types = [self.get_bc_ty(t) for t in ty.kind.parameter_types]
            return_type = self.get_bc_ty(ty.kind.return_type)
            return bc.FunctionType(param_types, return_type)
        elif ty.is_void():
            return bc.BaseTyp(bc.SimpleTyp.VOID)
        elif ty.is_unreachable():
            return bc.BaseTyp(bc.SimpleTyp.VOID)
        elif ty.is_type_parameter_ref():
            return bc.BaseTyp(bc.SimpleTyp.PTR)
        elif ty.is_array():
            ety = self.get_bc_ty(ty.kind.element_type)
            return bc.ArrayTyp(ety, ty.kind.size)
        elif ty.is_pointer():
            ety = self.get_bc_ty(ty.kind.element_type)
            return bc.PointerTyp(ety)
        elif ty.is_opaque():
            return bc.BaseTyp(bc.SimpleTyp.PTR)
        else:
            raise NotImplementedError(str(ty))

    def gen_struct(self, struct_def: ast.StructDef):
        logger.debug(f"generating bytecode type for struct {struct_def.id}")
        assert not struct_def.is_union
        ts = [self.get_bc_ty(field.ty) for field in struct_def.fields]
        self._types.append((struct_def.id.name, ts))

    def gen_function(self, func_def: ast.FunctionDef):
        logger.debug(f"generating bytecode for function {func_def.id}")
        self._code = []
        self._locals = []  # parameters and local variables
        self._local_typs = []
        params = []
        self._label_map = {}
        for parameter in func_def.parameters:
            self._locals.append(parameter)
            params.append(self.get_bc_ty(parameter.ty))

        if func_def.statement.ty.is_void():
            self.gen_statement(func_def.statement, None)
            self.emit(OpCode.RETURN, 0)
        elif func_def.statement.ty.is_unreachable():
            self.gen_statement(func_def.statement, None)
        else:
            variable = ast.Variable(
                ast.Id("_SNAG", 0), func_def.statement.ty, func_def.location
            )
            index = self.new_local(variable)
            self.gen_statement(func_def.statement, index)
            self.emit(OpCode.LOCAL_GET, index)
            self.emit(OpCode.RETURN, 1)

        # Fix labels:
        code = []
        for opcode, operands in self._code:
            if opcode == OpCode.JUMP:
                operands = (self._label_map[operands[0]],)
            elif opcode == OpCode.JUMP_IF:
                operands = (self._label_map[operands[0]], self._label_map[operands[1]])
            elif opcode == OpCode.SETUP_EXCEPT:
                operands = (self._label_map[operands[0]],)
            code.append((opcode, operands))

        ret_ty = self.get_bc_ty(func_def.return_ty)
        self._functions.append(
            bc.Function(
                self.get_id(func_def.id), code, params, self._local_typs, ret_ty
            )
        )

    def goto_inner_loop(self) -> LoopBlock:
        for block in self._loops:
            if isinstance(block, LoopBlock):
                return block
            elif isinstance(block, TryBlock):
                self.emit(OpCode.POP_EXCEPT)
        raise RuntimeError("No in a loop!")

    def enter_block(self, block):
        self._loops.insert(0, block)

    def leave_block(self):
        self._loops.pop(0)

    def gen_statement(self, statement: ast.Statement, target):
        kind = statement.kind
        if isinstance(kind, ast.LetStatement):
            index = self.new_local(kind.variable)
            if isinstance(kind.value.kind, ast.StatementExpression):
                self.gen_statement(kind.value.kind.statement, index)
            else:
                self.gen_expression(kind.value)
                self.emit(OpCode.LOCAL_SET, index)
        elif isinstance(kind, ast.CompoundStatement):
            for s in kind.statements[:-1]:
                self.gen_statement(s, None)
            self.gen_statement(kind.statements[-1], target)
        elif isinstance(kind, ast.BreakStatement):
            loop = self.goto_inner_loop()
            self.emit(OpCode.JUMP, loop.final_label)
        elif isinstance(kind, ast.ContinueStatement):
            loop = self.goto_inner_loop()
            self.emit(OpCode.JUMP, loop.start_label)
        elif isinstance(kind, ast.PassStatement):
            pass
        elif isinstance(kind, ast.UnreachableStatement):
            self.emit(OpCode.UNREACHABLE)
        elif isinstance(kind, ast.WhileStatement):
            start_label = self.new_label()
            body_label = self.new_label()
            final_label = self.new_label()

            self.emit(OpCode.JUMP, start_label)

            self.enter_block(LoopBlock(start_label, final_label))

            self.set_label(start_label)
            self.gen_expression(kind.condition)
            self.emit(OpCode.JUMP_IF, body_label, final_label)

            self.set_label(body_label)
            self.gen_statement(kind.block.body, None)
            self.emit(OpCode.JUMP, start_label)

            self.leave_block()

            self.set_label(final_label)
        elif isinstance(kind, ast.IfStatement):
            true_label = self.new_label()
            false_label = self.new_label()
            final_label = self.new_label()
            self.gen_expression(kind.condition)
            self.emit(OpCode.JUMP_IF, true_label, false_label)

            self.set_label(true_label)
            self.gen_statement(kind.true_block.body, target)
            self.emit(OpCode.JUMP, final_label)

            self.set_label(false_label)
            self.gen_statement(kind.false_block.body, target)
            self.emit(OpCode.JUMP, final_label)

            self.set_label(final_label)

        elif isinstance(kind, ast.ExpressionStatement):
            self.gen_expression(kind.value)
            if kind.value.ty.is_void():
                assert target is None
            elif kind.value.ty.is_unreachable():
                pass
            else:
                assert target is not None
                self.emit(OpCode.LOCAL_SET, target)

        elif isinstance(kind, ast.SwitchStatement):
            raise NotImplementedError("switch")
        elif isinstance(kind, ast.AssignmentStatement):
            if isinstance(kind.target.kind, ast.ObjRef):
                obj = kind.target.kind.obj
                if isinstance(obj, ast.Variable):
                    local_index = self._locals.index(obj)
                    if kind.op == "=":
                        self.gen_expression(kind.value)
                    else:
                        self.emit(OpCode.LOCAL_GET, local_index)
                        self.gen_expression(kind.value)
                        ty = self.get_bc_ty(kind.value.ty)
                        self.emit(self._binop_map[kind.op[:-1]], ty)
                    self.emit(OpCode.LOCAL_SET, local_index)
                elif isinstance(obj, ast.VarDef):  # Global!
                    global_index = self._type_map[id(obj)]
                    if kind.op == "=":
                        self.gen_expression(kind.value)
                    else:
                        self.emit(OpCode.GLOBAL_GET, global_index)
                        self.gen_expression(kind.value)
                        raise NotImplementedError("global +=")
                    self.emit(OpCode.GLOBAL_SET, global_index)
                else:
                    raise ValueError(f"Cannot assign obj: {obj}")
            elif isinstance(kind.target.kind, ast.DotOperator):
                self.gen_expression(kind.target.kind.base)
                index = kind.target.kind.base.ty.get_field_index(kind.target.kind.field)
                if kind.op == "=":
                    self.gen_expression(kind.value)
                else:
                    # Implement += and -= and friends
                    self.emit(OpCode.DUP)
                    ty = self.get_bc_ty(kind.value.ty)
                    self.emit(OpCode.GET_ATTR, index, ty)
                    self.gen_expression(kind.value)
                    self.emit(self._binop_map[kind.op[:-1]], ty)
                self.emit(OpCode.SET_ATTR, index)
            elif isinstance(kind.target.kind, ast.ArrayIndex):
                assert kind.op == "="
                self.gen_expression(kind.target.kind.base)
                assert len(kind.target.kind.indici) == 1
                self.gen_expression(kind.target.kind.indici[0])
                self.gen_expression(kind.value)
                self.emit(OpCode.SET_INDEX)
            else:
                raise ValueError(f"Cannot assign: {kind.target}")
        elif isinstance(kind, ast.ReturnStatement):
            if kind.value:
                self.gen_expression(kind.value)
                self.emit(OpCode.RETURN, 1)
            else:
                self.emit(OpCode.RETURN, 0)
        elif isinstance(kind, ast.RaiseStatement):
            self.gen_expression(kind.value)
            self.emit(OpCode.RAISE)
        elif isinstance(kind, ast.TryStatement):
            self._locals.append(kind.parameter)
            self._local_typs.append(self.get_bc_ty(kind.parameter.ty))

            final_label = self.new_label()
            except_label = self.new_label()

            self.emit(OpCode.SETUP_EXCEPT, except_label)
            self.enter_block(TryBlock())
            self.gen_statement(kind.try_block.body, None)
            self.leave_block()
            self.emit(OpCode.POP_EXCEPT)
            self.emit(OpCode.JUMP, final_label)

            self.set_label(except_label)
            local_index = self._locals.index(kind.parameter)
            self.emit(OpCode.LOCAL_SET, local_index)

            self.gen_statement(kind.except_block.body, None)
            self.emit(OpCode.JUMP, final_label)

            self.set_label(final_label)
        else:
            raise NotImplementedError(str(kind))

    def gen_expression(self, expression: ast.Expression):
        kind = expression.kind

        if isinstance(kind, ast.NumericConstant):
            self.emit(OpCode.CONST, kind.value)
        elif isinstance(kind, ast.StringConstant):
            self.emit(OpCode.CONST, kind.text)
        elif isinstance(kind, ast.BoolLiteral):
            self.emit(OpCode.CONST, kind.value)
        elif isinstance(kind, ast.CharConstant):
            self.emit(OpCode.CONST, kind.text)
        elif isinstance(kind, ast.StructLiteral):
            for value in kind.values:
                self.gen_expression(value)
            ty = bc.StructTyp(self._type_map[id(kind.ty.kind.tycon)])
            self.emit(
                OpCode.STRUCT_LITERAL,
                len(kind.values),
                ty,
            )
        elif isinstance(kind, ast.ArrayLiteral):
            for value in kind.values:
                self.gen_expression(value)
            self.emit(OpCode.ARRAY_LITERAL, len(kind.values))
        elif isinstance(kind, ast.ArrayLiteral2):
            self.gen_expression(kind.size)
            to_ty = self.get_bc_ty(kind.ty)
            self.emit(OpCode.ARRAY_LITERAL2, to_ty)
        elif isinstance(kind, ast.ArrayIndex):
            self.gen_expression(kind.base)
            assert len(kind.indici) == 1
            self.gen_expression(kind.indici[0])
            self.emit(OpCode.GET_INDEX)
        elif isinstance(kind, ast.Binop):
            # TBD: implement short circuit logic operations?
            # For example: 'false and expensive_function()'
            # should not call expensive_function
            self.gen_expression(kind.lhs)
            self.gen_expression(kind.rhs)

            if kind.op in self._binop_map:
                ty = self.get_bc_ty(kind.lhs.ty)
                self.emit(self._binop_map[kind.op], ty)
            else:
                raise NotImplementedError(str(kind.op))
        elif isinstance(kind, ast.Unop):
            self.gen_expression(kind.rhs)

            if kind.op in self._unop_map:
                self.emit(self._unop_map[kind.op])
            else:
                raise NotImplementedError(str(kind.op))
        elif isinstance(kind, ast.TypeCast):
            self.gen_expression(kind.value)
            to_ty = self.get_bc_ty(kind.ty)
            self.emit(OpCode.CAST, to_ty)
        elif isinstance(kind, ast.Box):
            self.gen_expression(kind.value)
        elif isinstance(kind, ast.Unbox):
            self.gen_expression(kind.value)
        elif isinstance(kind, ast.FunctionCall):
            for arg in kind.args:
                self.gen_expression(arg.value)
            self.gen_expression(kind.target)
            ret_ty = self.get_bc_ty(expression.ty)
            self.emit(OpCode.CALL, len(kind.args), ret_ty)
        elif isinstance(kind, ast.DotOperator):
            self.gen_expression(kind.base)
            index = kind.base.ty.get_field_index(kind.field)
            ty = kind.base.ty.get_field_type(kind.field)
            ty = self.get_bc_ty(ty)
            self.emit(OpCode.GET_ATTR, index, ty)
        elif isinstance(kind, ast.ObjRef):
            obj = kind.obj
            if isinstance(obj, (ast.Variable, ast.Parameter)):
                # TODO: use integer index!?
                idx = self._locals.index(obj)
                self.emit(OpCode.LOCAL_GET, idx)
            elif isinstance(obj, ast.FunctionDef):
                self.emit(OpCode.LOADFUNC, self.get_id(obj.id))
            elif isinstance(obj, ast.VarDef):
                global_index = self._type_map[id(obj)]
                self.emit(OpCode.GLOBAL_GET, global_index)
            elif isinstance(obj, ast.ExternFunction):
                self.emit(OpCode.BUILTIN, f"{obj.modname}_{obj.id.name}")
            else:
                raise NotImplementedError(str(obj))
        elif isinstance(kind, ast.StatementExpression):
            raise RuntimeError("can not use StatementExpression")
        elif isinstance(kind, ast.IfExpression):
            variable = ast.Variable(
                ast.Id("_TMP", 0), kind.true_value.ty, kind.true_value.location
            )
            target = self.new_local(variable)

            true_label = self.new_label()
            false_label = self.new_label()
            final_label = self.new_label()
            self.gen_expression(kind.condition)
            self.emit(OpCode.JUMP_IF, true_label, false_label)

            self.set_label(true_label)
            self.gen_expression(kind.true_value)
            self.emit(OpCode.LOCAL_SET, target)
            self.emit(OpCode.JUMP, final_label)

            self.set_label(false_label)
            self.gen_expression(kind.false_value)
            self.emit(OpCode.LOCAL_SET, target)
            self.emit(OpCode.JUMP, final_label)

            self.set_label(final_label)
            self.emit(OpCode.LOCAL_GET, target)
        else:
            raise NotImplementedError(str(kind))

    def new_local(self, variable):
        self._locals.append(variable)
        self._local_typs.append(self.get_bc_ty(variable.ty))
        return self._locals.index(variable)

    def get_id(self, id: ast.Id) -> str:
        if id.name == "main":
            return "main"
        return f"X{id.id}_{id.name}"

    def emit(self, opcode: bc.OpCode, *args):
        # print(f'    {len(self._code)} Op', opcode, args)
        self._code.append((opcode, args))

    def new_label(self) -> int:
        self._counter += 1
        return self._counter

    def set_label(self, label: int):
        # print('lab', label)
        self._label_map[label] = len(self._code)
