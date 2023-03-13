""" Type checker.
"""


import logging

from . import ast, types
from .basepass import BasePass
from .types import BaseType, FunctionType, StructType
from .types import bool_type, void_type

logger = logging.getLogger('typechecker')


class TypeChecker(BasePass):
    def __init__(self, code: str):
        super().__init__(code)
        assert self.types_equal(bool_type, bool_type)

    def check_module(self, module: ast.Module):
        for definition in module.definitions:
            if isinstance(definition, ast.StructDef):
                pass
            elif isinstance(definition, ast.FunctionDef):
                logger.debug(f"Checking function '{definition.name}'")
                self.check_function(definition)
            else:
                raise NotImplementedError(str(ty))

    def check_function(self, func):
        self._function = func
        self.visit_block(func.statements)
        self._function = None

    def visit_statement(self, statement: ast.Statement):
        super().visit_statement(statement)
        self.check_statement(statement)

    def check_statement(self, statement: ast.Statement):
        kind = statement.kind
        if isinstance(kind, ast.LoopStatement):
            pass
        elif isinstance(kind, ast.WhileStatement):
            self.assert_type(kind.condition, bool_type)
        elif isinstance(kind, ast.ForStatement):
            assert isinstance(kind.values.ty, types.ArrayType)
        elif isinstance(kind, ast.IfStatement):
            self.assert_type(kind.condition, bool_type)
        elif isinstance(kind, ast.ExpressionStatement):
            # Check void type: Good idea?
            self.assert_type(kind.value, void_type)
        elif isinstance(kind, (ast.BreakStatement, ast.ContinueStatement)):
            # TODO!
            pass
        elif isinstance(kind, ast.ReturnStatement):
            if kind.value:
                if not self.types_equal(kind.value.ty, self._function.ty.return_type):
                    self.error(
                        statement.location, f"Returning wrong type {kind.value.ty} (should be {self._function.ty.return_type})")

        elif isinstance(kind, ast.LetStatement):
            if kind.ty:
                self.assert_type(kind.value, kind.ty)
                kind.variable.ty = kind.ty
            else:
                kind.variable.ty = kind.value.ty
        elif isinstance(kind, ast.AssignmentStatement):
            pass
        elif isinstance(statement, list):
            pass
        elif statement is None:
            pass
        else:
            raise NotImplementedError(str(statement))

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)
        self.check_expression(expression)

    def check_expression(self, expression: ast.Expression):
        """ Perform type checking on expression! """
        kind = expression.kind
        if isinstance(kind, (ast.NumericConstant, ast.StringConstant)):
            pass
        elif isinstance(kind, ast.ArrayLiteral):
            assert len(kind.values) > 0
            expression.ty = types.ArrayType(
                len(kind.values), kind.values[0].ty)
        elif isinstance(kind, ast.Binop):
            # Introduce some heuristics...
            if kind.op == '/':
                ty = types.float_type
            elif kind.lhs.ty.is_int() and kind.rhs.ty.is_float():
                ty = kind.rhs.ty
            else:
                ty = kind.lhs.ty

            self.assert_type(kind.lhs, ty)
            self.assert_type(kind.rhs, ty)

            if kind.op in ['<', '>', '<=', '>=', '==', '!=']:
                expression.ty = bool_type
            elif kind.op in ['and', 'or']:
                self.assert_type(kind.lhs, bool_type)
                self.assert_type(kind.rhs, bool_type)
                expression.ty = bool_type
            else:
                expression.ty = ty

        elif isinstance(kind, ast.DotOperator):
            if isinstance(kind.base.ty, StructType):
                if kind.base.ty.has_field(kind.field):
                    expression.ty = kind.base.ty.get_field(kind.field)
                else:
                    self.error(expression.location,
                               f'Struct has no field: {kind.field}')
                    expression.ty = void_type
            else:
                self.error(expression.location,
                           f'Cannot index: {kind.base.ty}')

        elif isinstance(kind, ast.ArrayIndex):
            if isinstance(kind.base.ty, types.ArrayType):
                expression.ty = kind.base.ty.element_type
            else:
                self.error(expression.location,
                           f"Indexing requires array type, not {kind.base.ty}")

        elif isinstance(kind, ast.FunctionCall):
            if isinstance(kind.target.ty, FunctionType):
                if len(kind.args) != len(kind.target.ty.parameter_types):
                    self.error(
                        expression.location, f'Got {len(kind.args)} arguments, expected {len(kind.target.ty.parameter_types)}')
                for arg, expected_ty in zip(kind.args, kind.target.ty.parameter_types):
                    if not self.types_equal(arg.ty, expected_ty):
                        self.error(
                            arg.location, f'Got {arg.ty}, but expected {expected_ty}')
                expression.ty = kind.target.ty.return_type
            else:
                self.error(expression.location,
                           f'Trying to call non-function type: {kind.target.ty}')

        elif isinstance(kind, ast.NewOp):
            raise ValueError("Must be rewritten before!")
        elif isinstance(kind, ast.NameRef):
            raise ValueError(f"Must be resolved: {kind}")
        elif isinstance(kind, ast.StructLiteral):
            assert len(kind.ty.struct_def.fields) == len(kind.values)
            for field, value in zip(kind.ty.struct_def.fields, kind.values):
                self.assert_type(value, field.ty)
            expression.ty = kind.ty
        elif isinstance(kind, ast.ObjRef):
            if isinstance(kind.obj, ast.Variable):
                expression.ty = kind.obj.ty
            elif isinstance(kind.obj, ast.BuiltinFunction):
                expression.ty = kind.obj.ty
            elif isinstance(kind.obj, ast.FunctionDef):
                expression.ty = kind.obj.get_type()
            elif isinstance(kind.obj, ast.Parameter):
                expression.ty = kind.obj.ty
            else:
                raise NotImplementedError(str(kind))
        else:
            raise NotImplementedError(str(expression.kind))

    def assert_type(self, expression: ast.Expression, ty: types.MyType):
        """ Check if expression is of given type, raise error otherwise.
        """
        # Try to auto-convert before check
        if expression.ty.is_int() and ty.is_float():
            # Auto-conv int to floats
            old_expr = expression.clone()
            expression.kind = ast.TypeCast(ty, old_expr)
            expression.ty = ty

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
