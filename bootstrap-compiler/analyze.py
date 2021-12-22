""" Type check code.
"""

import logging
from .ast import FunctionDef, StructDef
from .ast import Break, Continue, Return
from .ast import IfStatement, Loop, While, Let
from .ast import FunctionCall, Binop, NameRef
from .ast import NumericConstant, StringConstant
from .ast import DotOperator, NewOp
from .errors import print_error

from .symboltable import Scope
from .types import BaseType, FunctionType, ModuleType, StructType
from .types import str_type, int_type, bool_type, void_type

logger = logging.getLogger('analyzer')


def analyze_ast(ast, code):
    a = Analyzer(code)
    a.check_module(ast)
    return a._ok


def base_scope():
    top_scope = Scope(None)
    top_scope.define('std', BuiltinModule(
        'std', {
            'print': BuiltinFunction('std_print', [str_type], int_type),
        }))
    top_scope.define('str', str_type)
    top_scope.define('int', int_type)
    return top_scope


class Analyzer:
    def __init__(self, code):
        self._code = code
        self._ok = True
        self._scopes = [base_scope()]
        assert self.types_equal(bool_type, bool_type)

    def check_module(self, ast):
        self.enter_scope()
        for func in ast.imports:
            scope = self._scopes[-1]
            if scope.is_defined(func.name):
                scope.lookup(func.name)
            else:
                self.error(func.location, f'Undefined import: {func.name}')

        for typ in ast.types:
            if isinstance(typ, StructDef):
                fields = [
                    (f.name, self.check_type(f.ty))
                    for f in typ.fields
                ]
                ty = StructType(fields)
                typ.ty = ty
            else:
                raise NotImplementedError(str(ty))
            self.define_symbol(typ.name, ty)

        for func in ast.functions:
            self.define_symbol(func.name, func)
            parameter_types = [
                self.check_type(arg.ty) for arg in func.parameters
            ]
            return_type = self.check_type(func.return_ty)
            func.ty = FunctionType(parameter_types, return_type)

        for func in ast.functions:
            logger.debug(f'Checking function {func.name}')
            self.check_function(func)
        self.leave_scope()

    def check_type(self, ty):
        if ty is None:
            return void_type
        elif isinstance(ty, NameRef):
            ty = self.check_name(ty.name, ty.location)
            return ty
        else:
            raise NotImplementedError(str(ty))

    def check_name(self, name: str, location):
        assert isinstance(name, str), str(type(name))
        scope = self._scopes[-1]
        if scope.is_defined(name):
            obj = scope.lookup(name)
            assert obj
            return obj
        else:
            self.error(location, f'Undefined symbol: {name}')
            return Undefined()

    def check_function(self, func):
        self.enter_scope()
        self._function = func
        for parameter in func.parameters:
            parameter.ty = self.check_type(parameter.ty)
            self.define_symbol(parameter.name, parameter)

        for statement in func.statements:
            self.check_statement(statement)
        self.leave_scope()
        self._function = None

    def check_statement(self, statement):
        if isinstance(statement, Loop):
            self.check_statement(statement.inner)
        elif isinstance(statement, While):
            self.check_statement(statement.inner)
        elif isinstance(statement, IfStatement):
            self.check_expression(statement.condition)
            self.check_statement(statement.true_statement)
            self.check_statement(statement.false_statement)
        elif isinstance(statement, FunctionCall):
            self.check_expression(statement)
        elif isinstance(statement, Break):
            # TODO!
            pass
        elif isinstance(statement, Continue):
            # TODO!
            pass
        elif isinstance(statement, Return):
            statement.value = self.check_expression(statement.value)
            if not self.types_equal(statement.value.ty, self._function.ty.return_type):
                self.error(
                    statement.location, f"Returning wrong type {statement.value.ty} (should be {self._function.ty.return_type})")

        elif isinstance(statement, Let):
            statement.value = self.check_expression(statement.value)
            variable = Variable(statement.target, statement.value.ty)
            statement.variable = variable
            self.define_symbol(statement.target, variable)
        elif isinstance(statement, list):
            for s in statement:
                self.check_statement(s)
        elif statement is None:
            pass
        else:
            raise NotImplementedError(str(statement))

    def check_expression(self, expression):
        if isinstance(expression, NumericConstant):
            expression.ty = int_type
        elif isinstance(expression, StringConstant):
            expression.ty = str_type
        elif isinstance(expression, Binop):
            self.check_binop(expression)
        elif isinstance(expression, DotOperator):
            expression = self.check_dot_operator(expression)
        elif isinstance(expression, FunctionCall):
            self.check_function_call(expression)
        elif isinstance(expression, NewOp):
            self.check_new_op(expression)

        elif isinstance(expression, NameRef):
            expression = self.check_name(expression.name, expression.location)
        else:
            raise NotImplementedError(str(expression))
        return expression

    def check_dot_operator(self, expression):
        expression.base = self.check_expression(expression.base)
        # print(base_ty)
        if isinstance(expression.base, BuiltinModule):
            expression = expression.base.symbols[expression.field]
        elif isinstance(expression.base.ty, StructType):
            if expression.base.ty.has_field(expression.field):
                _, expression.ty = expression.base.ty.get_field(
                    expression.field)

            else:
                self.error(expression.location,
                           f'Struct has no field: {expression.field}')
                expression.ty = void_type
        else:
            self.error(expression.location,
                       f'Cannot index: {expression.base.ty}')
            expression.ty = void_type
        # if not base_ty.has_field(expression.field):
        #     self.error(expression.location,
        #                f'Field {expression.field} not found!')
        return expression

    def check_new_op(self, expression: NewOp):
        # print('new op', expression.ty, expression.fields)
        expression.new_ty = self.check_type(expression.new_ty)
        expression.ty = expression.new_ty
        if expression.new_ty.is_struct():
            filled = set()
            required = {f for f, _ in expression.new_ty.fields}
            for field in expression.fields:
                if field.name in required:
                    required.remove(field.name)
                    field.value = self.check_expression(field.value)
                    # TODO: type check value!
                elif field.name in filled:
                    # Field was already filled
                    self.error(field.location,
                               f"Field {field.name} double initialized")
                else:
                    # Field is not needed
                    self.error(field.location,
                               f"Field {field.name} does not exist")

                filled.add(field.name)
            if required:
                self.error(expression.location,
                           f'Missing fields: {required}')
        else:
            self.error(
                expression.location, f'Can only contrap struct type, not {expression.new_ty}')
        # Check that all fields are filled!

    def check_function_call(self, expression: FunctionCall):
        expression.target = self.check_expression(expression.target)
        if isinstance(expression.target.ty, FunctionType):
            if len(expression.args) != len(expression.target.ty.parameter_types):
                self.error(
                    expression.location, f'Got {len(expression.args)} arguments, expected {len(expression.target.ty.parameter_types)}')
            new_args = []
            for arg, expected_ty in zip(expression.args, expression.target.ty.parameter_types):
                arg2 = self.check_expression(arg)
                if not self.types_equal(arg2.ty, expected_ty):
                    self.error(
                        arg.location, f'Got {arg2.ty}, but expected {expected_ty}')
                new_args.append(arg2)
            expression.args = new_args
            expression.ty = expression.target.ty.return_type
        else:
            self.error(expression.location,
                       f'Trying to call non-function type: {expression.target.ty}')

            expression.ty = void_type

    def check_binop(self, expression):
        expression.lhs = self.check_expression(expression.lhs)
        expression.rhs = self.check_expression(expression.rhs)
        if not self.types_equal(expression.lhs.ty, expression.rhs.ty):
            self.error(
                expression.location, f'Unequal types "{expression.lhs.ty}" and "{expression.rhs.ty}"')

        if expression.op in ['<', '>', '<=', '>=', '==', '!=']:
            expression.ty = bool_type
        elif expression.op in ['and', 'or']:
            self.assert_type(expression.lhs, bool_type)
            self.assert_type(expression.rhs, bool_type)
            expression.ty = bool_type
        else:
            expression.ty = expression.lhs.ty

    def assert_type(self, expression, ty):
        """ Check if expression is of given type, raise error otherwise.
        """
        if not self.types_equal(expression.ty, ty):
            self.error(
                expression.location,
                f"Type error, got {expression.ty}, but expected {ty}"
            )

    def types_equal(self, a_ty, b_ty):
        if a_ty is b_ty:
            return True
        elif isinstance(a_ty, BaseType) and isinstance(b_ty, BaseType):
            return a_ty.name == b_ty.name
        else:
            return False

    def enter_scope(self):
        parent_scope = self._scopes[-1]
        scope = Scope(parent_scope)
        self._scopes.append(scope)
        return scope

    def leave_scope(self):
        self._scopes.pop()

    def define_symbol(self, name: str, symbol):
        assert isinstance(name, str)
        scope = self._scopes[-1]
        if scope.is_defined(name, search_parents=False):
            self.error(symbol.location, f'{name} is already defined')
        else:
            scope.define(name, symbol)

    def error(self, location, msg):
        print("**************** ERROR *******************")
        print_error(self._code, location, msg)
        print("******************************************")
        self._ok = False


class Variable:
    def __init__(self, name, ty):
        super().__init__()
        self.name = name
        self.ty = ty

    def __repr__(self):
        return f'var({self.name})'


class BuiltinModule:
    def __init__(self, name, symbols):
        super().__init__()
        self.name = name
        self.ty = ModuleType()
        self.symbols = symbols


class BuiltinFunction:
    def __init__(self, name, parameter_types, return_type):
        self.name = name
        self.ty = FunctionType(parameter_types, return_type)


class Undefined:
    def __init__(self):
        self.ty = void_type
