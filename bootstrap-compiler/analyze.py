""" Type check code.
"""

import logging
from . import ast, types
from .errors import print_error
from .location import Location

from .symboltable import Scope
from .types import BaseType, FunctionType, ModuleType, StructType
from .types import str_type, int_type, bool_type, void_type, float_type

logger = logging.getLogger('analyzer')


def analyze_ast(module: ast.Module, code: str):
    logger.info("Type checking")
    a = Analyzer(code)
    a.check_module(module)
    return a._ok


def base_scope():
    top_scope = Scope(None)
    top_scope.define('std', ast.BuiltinModule(
        'std', {
            'print': ast.BuiltinFunction('std_print', [str_type], int_type),
            'int_to_str': ast.BuiltinFunction('std_int_to_str', [int_type], str_type),
        }))
    top_scope.define('str', str_type)
    top_scope.define('int', int_type)
    top_scope.define('float', float_type)
    return top_scope


class BasePass(ast.AstVisitor):
    pass


class ScopeFiller(BasePass):
    pass


class Analyzer:
    def __init__(self, code):
        self._code = code
        self._ok = True
        self._scopes = [base_scope()]
        assert self.types_equal(bool_type, bool_type)

    def check_module(self, module: ast.Module):
        self.enter_scope()
        for func in module.imports:
            scope = self._scopes[-1]
            if scope.is_defined(func.name):
                scope.lookup(func.name)
            else:
                self.error(func.location, f'Undefined import: {func.name}')

        for definition in module.definitions:
            if isinstance(definition, ast.StructDef):
                fields = [
                    (f.name, self.check_type(f.ty))
                    for f in definition.fields
                ]
                ty = StructType(fields)
                definition.ty = ty
                self.define_symbol(definition.name, ty)
            elif isinstance(definition, ast.FunctionDef):
                self.define_symbol(definition.name, definition)
                parameter_types = [
                    self.check_type(arg.ty) for arg in definition.parameters
                ]
                return_type = self.check_type(definition.return_ty)
                definition.ty = FunctionType(parameter_types, return_type)
            else:
                raise NotImplementedError(str(ty))

        for definition in module.definitions:
            if isinstance(definition, ast.FunctionDef):
                logger.debug(f'Checking function {definition.name}')
                self.check_function(definition)

        self.leave_scope()

    def check_type(self, ty):
        if ty is None:
            return void_type
        elif isinstance(ty, ast.NameRef):
            ty = self.check_name(ty.name, ty.location)
            return ty
        else:
            raise NotImplementedError(str(ty) + str(type(ty)))

    def check_name(self, name: str, location: Location):
        assert isinstance(name, str), str(type(name))
        scope = self._scopes[-1]
        if scope.is_defined(name):
            obj = scope.lookup(name)
            assert obj
            return obj
        else:
            self.error(location, f'Undefined symbol: {name}')
            return ast.Undefined()

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

    def check_statement(self, statement: ast.Statement):
        if isinstance(statement, ast.Loop):
            self.check_statement(statement.inner)
        elif isinstance(statement, ast.While):
            self.check_statement(statement.inner)
        elif isinstance(statement, ast.ForStatement):
            statement.values = self.check_expression(statement.values)
            assert isinstance(statement.values.ty, types.ArrayType)
            variable = ast.Variable(
                statement.target, statement.values.ty.element_type)
            self.define_symbol(statement.target, variable)
            self.check_statement(statement.inner)
        elif isinstance(statement, ast.IfStatement):
            statement.condition = self.check_expression(statement.condition)
            self.check_statement(statement.true_statement)
            self.check_statement(statement.false_statement)
        elif isinstance(statement, ast.FunctionCall):
            self.check_expression(statement)
        elif isinstance(statement, ast.Break):
            # TODO!
            pass
        elif isinstance(statement, ast.Continue):
            # TODO!
            pass
        elif isinstance(statement, ast.Return):
            if statement.value:
                statement.value = self.check_expression(statement.value)
                if not self.types_equal(statement.value.ty, self._function.ty.return_type):
                    self.error(
                        statement.location, f"Returning wrong type {statement.value.ty} (should be {self._function.ty.return_type})")

        elif isinstance(statement, ast.Let):
            statement.value = self.check_expression(statement.value)
            variable = ast.Variable(statement.target, statement.value.ty)
            statement.variable = variable
            statement.ty = variable.ty
            self.define_symbol(statement.target, variable)
        elif isinstance(statement, ast.Assignment):
            statement.value = self.check_expression(statement.value)

        elif isinstance(statement, list):
            for s in statement:
                self.check_statement(s)
        elif statement is None:
            pass
        else:
            raise NotImplementedError(str(statement))

    def check_expression(self, expression: ast.Expression) -> ast.Expression:
        if isinstance(expression, ast.NumericConstant):
            if isinstance(expression.value, float):
                expression.ty = float_type
            else:
                expression.ty = int_type
        elif isinstance(expression, ast.StringConstant):
            expression.ty = str_type
        elif isinstance(expression, ast.ArrayLiteral):
            assert len(expression.values) > 0
            expression.values = [
                self.check_expression(e) for e in expression.values
            ]
            expression.ty = types.ArrayType(
                len(expression.values), expression.values[0].ty)
        elif isinstance(expression, ast.Binop):
            self.check_binop(expression)
        elif isinstance(expression, ast.DotOperator):
            expression = self.check_dot_operator(expression)
        elif isinstance(expression, ast.ArrayIndex):
            expression.base = self.check_expression(expression.base)
            assert isinstance(expression.base.ty, types.ArrayType)
            expression.ty = expression.base.ty.element_type
        elif isinstance(expression, ast.FunctionCall):
            self.check_function_call(expression)
        elif isinstance(expression, ast.NewOp):
            self.check_new_op(expression)
        elif isinstance(expression, ast.NameRef):
            expression = self.check_name(expression.name, expression.location)
        else:
            raise NotImplementedError(str(expression))
        return expression

    def check_dot_operator(self, expression):
        expression.base = self.check_expression(expression.base)
        # print(base_ty)
        if isinstance(expression.base, ast.BuiltinModule):
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

    def check_new_op(self, expression: ast.NewOp):
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

    def check_function_call(self, expression: ast.FunctionCall):
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

    def check_binop(self, expression: ast.Binop):
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

    def assert_type(self, expression: ast.Expression, ty: types.MyType):
        """ Check if expression is of given type, raise error otherwise.
        """
        if not self.types_equal(expression.ty, ty):
            self.error(
                expression.location,
                f"Type error, got {expression.ty}, but expected {ty}"
            )

    def types_equal(self, a_ty: types.MyType, b_ty: types.MyType):
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

    def error(self, location: Location, msg: str):
        print("**************** ERROR *******************")
        print_error(self._code, location, msg)
        print("******************************************")
        self._ok = False
