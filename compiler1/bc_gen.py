""" Generate bytecode from AST.
"""

import logging
from . import ast
from .vm import run_bytecode
from . import vm

logger = logging.getLogger('bytecode-gen')


def gen_bc(modules: list[ast.Module]) -> vm.Program:
    logger.info('generating bytecode')
    g = ByteCodeGenerator()
    for module in modules:
        g.gen_module(module)

    return vm.Program(g._functions)


class ByteCodeGenerator:
    def __init__(self):
        self._counter = 0
        self._loops = []
        self._functions = []
        self._code = []
        self._locals = []
        self._label_map = {}

    def gen_module(self, module: ast.Module):
        for definition in module.definitions:
            if isinstance(definition, ast.FunctionDef):
                self.gen_function(definition)
            else:
                # raise NotImplementedError(str(definition))
                pass

    def gen_function(self, func_def: ast.FunctionDef):
        logger.debug(f'generating bytecode for {func_def.name}')
        # print(f'fn {func_def.name}')
        self._code = []
        self._locals = []  # parameters and local variables
        self._label_map = {}
        for parameter in func_def.parameters:
            self._locals.append(parameter)
        self.gen_statement(func_def.statements)
        self.emit('RETURN', 0)

        # Fix labels:
        code = []
        for opcode, operands in self._code:
            if opcode == 'JUMP':
                operands = (self._label_map[operands[0]],)
            elif opcode == 'JUMP-IF':
                operands = (self._label_map[operands[0]],
                            self._label_map[operands[1]])
            # print(f'  {len(code)} OP2', opcode, operands)
            code.append((opcode, operands))

        n_locals = len(self._locals)
        self._functions.append(vm.Function(func_def.name, code, n_locals))

    def gen_statement(self, statement: ast.Statement):
        kind = statement.kind
        if isinstance(kind, ast.LetStatement):
            self.gen_expression(kind.value)
            self._locals.append(kind.variable)
            self.emit('LOCAL_SET', self._locals.index(kind.variable))
        elif isinstance(kind, ast.CompoundStatement):
            for s in kind.statements:
                self.gen_statement(s)
        elif isinstance(kind, ast.BreakStatement):
            self.emit('JUMP', self._loops[-1][1])
        elif isinstance(kind, ast.ContinueStatement):
            self.emit('JUMP', self._loops[-1][0])
        elif isinstance(kind, ast.PassStatement):
            pass
        elif isinstance(kind, ast.WhileStatement):
            start_label = self.new_label()
            body_label = self.new_label()
            final_label = self.new_label()

            self.emit('JUMP', start_label)

            self._loops.append((start_label, final_label))

            self.set_label(start_label)
            self.gen_expression(kind.condition)
            self.emit('JUMP-IF', body_label, final_label)

            self.set_label(body_label)
            self.gen_statement(kind.inner)
            self.emit('JUMP', start_label)

            self._loops.pop()

            self.set_label(final_label)
        elif isinstance(kind, ast.IfStatement):
            true_label = self.new_label()
            false_label = self.new_label()
            final_label = self.new_label()
            self.gen_expression(kind.condition)
            self.emit('JUMP-IF', true_label, false_label)

            self.set_label(true_label)
            self.gen_statement(kind.true_statement)
            self.emit('JUMP', final_label)

            self.set_label(false_label)
            self.gen_statement(kind.false_statement)
            self.emit('JUMP', final_label)

            self.set_label(final_label)

        elif isinstance(kind, ast.ExpressionStatement):
            self.gen_expression(kind.value)

        elif isinstance(kind, ast.SwitchStatement):
            raise NotImplementedError('switch')
        elif isinstance(kind, ast.AssignmentStatement):
            self.gen_expression(kind.value)
            if isinstance(kind.target.kind, ast.ObjRef):
                obj = kind.target.kind.obj
                if isinstance(obj, ast.Variable):
                    self.emit('LOCAL_SET', self._locals.index(obj))
                else:
                    raise ValueError(f'Cannot assign obj: {obj}')
            elif isinstance(kind.target.kind, ast.DotOperator):
                self.gen_expression(kind.target.kind.base)
                index = kind.target.kind.base.ty.get_field_index(
                    kind.target.kind.field)
                self.emit('SET_ATTR', index)
            elif isinstance(kind.target.kind, ast.ArrayIndex):
                self.gen_expression(kind.target.kind.base)
                self.gen_expression(kind.target.kind.index)
                self.emit('SET_INDEX')
            else:
                raise ValueError(f'Cannot assign: {kind.target}')
        elif isinstance(kind, ast.ReturnStatement):
            if kind.value:
                self.gen_expression(kind.value)
                self.emit('RETURN', 1)
            else:
                self.emit('RETURN', 0)
        else:
            raise NotImplementedError(str(kind))

    def gen_expression(self, expression: ast.Expression):
        kind = expression.kind

        if isinstance(kind, ast.NumericConstant):
            self.emit('CONST', kind.value)
        elif isinstance(kind, ast.StringConstant):
            self.emit('CONST', kind.text)
        elif isinstance(kind, ast.BoolLiteral):
            self.emit('CONST', kind.value)
        elif isinstance(kind, ast.StructLiteral):
            for value in kind.values:
                self.gen_expression(value)
            self.emit('STRUC_LIT', len(kind.values))
        elif isinstance(kind, ast.ArrayLiteral):
            for value in kind.values:
                self.gen_expression(value)
            self.emit('ARRAY_LIT', len(kind.values))
        elif isinstance(kind, ast.ArrayIndex):
            self.gen_expression(kind.base)
            self.gen_expression(kind.index)
            self.emit('GET_INDEX')
        elif isinstance(kind, ast.UnionLiteral):
            self.gen_expression(kind.value)
            index = kind.ty.get_field_index(kind.field)
            self.emit('UNION_LIT', index)
        elif isinstance(kind, ast.Binop):
            # TBD: implement short circuit logic operations?
            # For example: 'false and expensive_function()'
            # should not call expensive_function
            self.gen_expression(kind.lhs)
            self.gen_expression(kind.rhs)
            m = {
                '+': 'ADD', '-': 'SUB', '*': 'MUL', '/': 'DIV',
                '<': 'LT', '>': 'GT', '<=': 'LTE', '>=': 'GTE',
                '==': 'EQ',
                'and': 'AND', 'or': 'OR'
            }
            if kind.op in m:
                self.emit(m[kind.op])
            else:
                raise NotImplementedError(str(kind.op))
        elif isinstance(kind, ast.TypeCast):
            # TODO!
            self.gen_expression(kind.value)
            pass
        elif isinstance(kind, ast.FunctionCall):
            for arg in kind.args:
                self.gen_expression(arg)
            self.gen_expression(kind.target)
            self.emit('CALL', len(kind.args))
        elif isinstance(kind, ast.DotOperator):
            self.gen_expression(kind.base)
            index = kind.base.ty.get_field_index(kind.field)
            self.emit('GET_ATTR', index)
        elif isinstance(kind, ast.ObjRef):
            obj = kind.obj
            if isinstance(obj, (ast.Variable, ast.Parameter)):
                # TODO: use integer index!?
                idx = self._locals.index(obj)
                self.emit('LOCAL_GET', idx)
            elif isinstance(obj, ast.FunctionDef):
                self.emit('LOADFUNC', obj.name)
            elif isinstance(obj, ast.BuiltinFunction):
                self.emit('BUILTIN', obj.name)
            else:
                raise NotImplementedError(str(obj))
        else:
            raise NotImplementedError(str(kind))

    def emit(self, opcode, *args):
        # print(f'    {len(self._code)} Op', opcode, args)
        self._code.append((opcode, args))

    def new_label(self) -> int:
        self._counter += 1
        return self._counter

    def set_label(self, label: int):
        # print('lab', label)
        self._label_map[label] = len(self._code)
