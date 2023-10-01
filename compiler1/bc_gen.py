""" Generate bytecode from AST.
"""

import logging
from . import ast
from . import bc
from .bc import OpCode

logger = logging.getLogger("bytecode-gen")


def gen_bc(modules: list[ast.Module]) -> bc.Program:
    logger.info("generating bytecode")
    g = ByteCodeGenerator()
    for module in modules:
        g.gen_module(module)

    return bc.Program(g._types, g._functions)


class ByteCodeGenerator:
    def __init__(self):
        self._counter = 0
        self._loops = []
        self._functions = []
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
        }

        self._unop_map = {
            "not": OpCode.NOT,
            "-": OpCode.NEG,
        }

    def gen_module(self, module: ast.Module):
        # Forward declare types:
        cnt = 0
        for definition in module.definitions:
            if isinstance(definition, ast.StructDef):
                self._type_map[id(definition)] = cnt
                cnt += 1

        for definition in module.definitions:
            if isinstance(definition, ast.FunctionDef):
                self.gen_function(definition)
            elif isinstance(definition, ast.StructDef):
                self.gen_struct(definition)
            else:
                raise NotImplementedError(str(definition))

    def get_bc_ty(self, ty: ast.MyType) -> bc.Typ:
        if ty.is_int():
            return bc.BaseTyp(bc.SimpleTyp.INT)
        elif ty.is_str():
            return bc.BaseTyp(bc.SimpleTyp.STR)
        elif ty.is_float():
            return bc.BaseTyp(bc.SimpleTyp.FLOAT)
        elif ty.is_bool():
            return bc.BaseTyp(bc.SimpleTyp.BOOL)
        elif ty.is_struct() or ty.is_union():
            return bc.StructTyp(self._type_map[id(ty.kind.tycon)])
        elif ty.is_function():
            param_types = [self.get_bc_ty(t) for t in ty.kind.parameter_types]
            return_type = self.get_bc_ty(ty.kind.return_type)
            return bc.FunctionType(param_types, return_type)
        elif ty.is_void():
            return bc.BaseTyp(bc.SimpleTyp.VOID)
        elif ty.is_type_parameter_ref():
            return bc.BaseTyp(bc.SimpleTyp.PTR)
        elif ty.is_array():
            ety = self.get_bc_ty(ty.kind.element_type)
            return bc.ArrayTyp(ety, ty.kind.size)
        else:
            raise NotImplementedError(str(ty))

    def gen_struct(self, struct_def: ast.StructDef):
        logger.debug(f"generating bytecode type for struct {struct_def.name}")
        ts = []
        for field in struct_def.fields:
            t = self.get_bc_ty(field.ty)
            ts.append(t)
        self._types.append((struct_def.name, struct_def.is_union, ts))

    def gen_function(self, func_def: ast.FunctionDef):
        logger.debug(f"generating bytecode for function {func_def.name}")
        self._code = []
        self._locals = []  # parameters and local variables
        self._local_typs = []
        params = []
        self._label_map = {}
        for parameter in func_def.parameters:
            self._locals.append(parameter)
            params.append(self.get_bc_ty(parameter.ty))
        self.gen_statement(func_def.statements)
        ret_ty = self.get_bc_ty(func_def.return_ty)

        if len(self._code) == 0 or self._code[-1][0] != OpCode.RETURN:
            # TODO: emit implicit return?
            self.emit(OpCode.RETURN, 0)

        # Fix labels:
        code = []
        for opcode, operands in self._code:
            if opcode == OpCode.JUMP:
                operands = (self._label_map[operands[0]],)
            elif opcode == OpCode.JUMP_IF:
                operands = (self._label_map[operands[0]], self._label_map[operands[1]])
            elif opcode == OpCode.SETUP_EXCEPT:
                operands = (self._label_map[operands[0]],)
            # print(f'  {len(code)} OP2', opcode, operands)
            code.append((opcode, operands))

        self._functions.append(
            bc.Function(func_def.name, code, params, self._local_typs, ret_ty)
        )

    def gen_statement(self, statement: ast.Statement):
        kind = statement.kind
        if isinstance(kind, ast.LetStatement):
            self.gen_expression(kind.value)
            self._locals.append(kind.variable)
            self._local_typs.append(self.get_bc_ty(kind.variable.ty))
            self.emit(OpCode.LOCAL_SET, self._locals.index(kind.variable))
        elif isinstance(kind, ast.CompoundStatement):
            for s in kind.statements:
                self.gen_statement(s)
        elif isinstance(kind, ast.BreakStatement):
            self.emit(OpCode.JUMP, self._loops[-1][1])
        elif isinstance(kind, ast.ContinueStatement):
            self.emit(OpCode.JUMP, self._loops[-1][0])
        elif isinstance(kind, ast.PassStatement):
            pass
        elif isinstance(kind, ast.WhileStatement):
            start_label = self.new_label()
            body_label = self.new_label()
            final_label = self.new_label()

            self.emit(OpCode.JUMP, start_label)

            self._loops.append((start_label, final_label))

            self.set_label(start_label)
            self.gen_expression(kind.condition)
            self.emit(OpCode.JUMP_IF, body_label, final_label)

            self.set_label(body_label)
            self.gen_statement(kind.block.body)
            self.emit(OpCode.JUMP, start_label)

            self._loops.pop()

            self.set_label(final_label)
        elif isinstance(kind, ast.IfStatement):
            true_label = self.new_label()
            false_label = self.new_label()
            final_label = self.new_label()
            self.gen_expression(kind.condition)
            self.emit(OpCode.JUMP_IF, true_label, false_label)

            self.set_label(true_label)
            self.gen_statement(kind.true_block.body)
            self.emit(OpCode.JUMP, final_label)

            self.set_label(false_label)
            self.gen_statement(kind.false_block.body)
            self.emit(OpCode.JUMP, final_label)

            self.set_label(final_label)

        elif isinstance(kind, ast.ExpressionStatement):
            self.gen_expression(kind.value)

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
            self.gen_statement(kind.try_block.body)
            self.emit(OpCode.POP_EXCEPT)
            self.emit(OpCode.JUMP, final_label)

            self.set_label(except_label)
            local_index = self._locals.index(kind.parameter)
            self.emit(OpCode.LOCAL_SET, local_index)

            self.gen_statement(kind.except_block.body)
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
        elif isinstance(kind, ast.ArrayIndex):
            self.gen_expression(kind.base)
            assert len(kind.indici) == 1
            self.gen_expression(kind.indici[0])
            self.emit(OpCode.GET_INDEX)
        elif isinstance(kind, ast.UnionLiteral):
            self.gen_expression(kind.value)
            index = kind.ty.get_field_index(kind.field)
            ty = bc.StructTyp(self._type_map[id(kind.ty.kind.tycon)])
            self.emit(OpCode.UNION_LITERAL, index, ty)
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
                self.emit(OpCode.LOADFUNC, obj.name)
            elif isinstance(obj, ast.BuiltinFunction):
                self.emit(OpCode.BUILTIN, obj.name)
            else:
                raise NotImplementedError(str(obj))
        else:
            raise NotImplementedError(str(kind))

    def emit(self, opcode: bc.OpCode, *args):
        # print(f'    {len(self._code)} Op', opcode, args)
        self._code.append((opcode, args))

    def new_label(self) -> int:
        self._counter += 1
        return self._counter

    def set_label(self, label: int):
        # print('lab', label)
        self._label_map[label] = len(self._code)
