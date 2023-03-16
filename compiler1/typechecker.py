""" Type checker.
"""


import logging

from . import ast, types
from .basepass import BasePass
from .location import Location
from .types import bool_type, void_type
from .errors import CompilationError

logger = logging.getLogger('typechecker')


class TypeChecker(BasePass):
    def __init__(self):
        super().__init__()

    def check_module(self, module: ast.Module):
        self.begin(module.filename, f"Type checking module '{module.name}'")
        for definition in module.definitions:
            if isinstance(definition, (ast.StructDef, ast.EnumDef, ast.TypeDef)):
                pass
            elif isinstance(definition, ast.FunctionDef):
                logger.debug(f"Checking function '{definition.name}'")
                self.check_function(definition)
            elif isinstance(definition, ast.ClassDef):
                logger.debug(f"Checking function '{definition.name}'")
                for inner_def in definition.members:
                    if isinstance(inner_def, ast.FunctionDef):
                        self.check_function(inner_def)
            else:
                raise NotImplementedError(str(definition))

        self.finish("Type check OK.")

    def check_function(self, func: ast.FunctionDef):
        self._function = func
        self.visit_statement(func.statements)
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
            pass
        elif isinstance(kind, ast.IfStatement):
            self.assert_type(kind.condition, bool_type)
        elif isinstance(kind, ast.CaseStatement):
            pass  # handled in mid-statement hook
        elif isinstance(kind, ast.SwitchStatement):
            self.assert_type(kind.value, types.int_type)
        elif isinstance(kind, ast.ExpressionStatement):
            # Check void type: Good idea?
            self.assert_type(kind.value, void_type)
        elif isinstance(kind, (ast.BreakStatement, ast.ContinueStatement)):
            # TODO!
            pass
        elif isinstance(kind, (ast.PassStatement, ast.CompoundStatement)):
            pass
        elif isinstance(kind, ast.ReturnStatement):
            if kind.value:
                if not kind.value.ty.equals(self._function.return_ty):
                    self.error(
                        statement.location, f"Returning wrong type {kind.value.ty} (should be {self._function.return_ty})")

        elif isinstance(kind, ast.LetStatement):
            if kind.ty:
                self.assert_type(kind.value, kind.ty)
                kind.variable.ty = kind.ty
            else:
                kind.variable.ty = kind.value.ty
        elif isinstance(kind, ast.AssignmentStatement):
            self.assert_type(kind.value, kind.target.ty)
        else:
            raise NotImplementedError(str(statement))

    def mid_statement(self, statement: ast.Statement):
        kind = statement.kind
        if isinstance(kind, ast.CaseStatement):
            if kind.value.ty.is_enum():
                enum_def: ast.EnumDef = kind.value.ty.kind.enum_def
                for arm in kind.arms:
                    if enum_def.scope.is_defined(arm.name):
                        variant: ast.EnumVariant = enum_def.scope.lookup(
                            arm.name)

                        # HACK to pass variant to transform pass:
                        arm.variant = variant

                        assert len(variant.payload) == len(arm.variables)
                        for v, t in zip(arm.variables, variant.payload):
                            v.ty = t
                        # TODO: check missing fields
                    else:
                        self.error(arm.location,
                                   f'No enum variant {arm.name}')
            else:
                self.error(kind.value.location,
                           f'Expected enum, not {kind.value.ty}')
        elif isinstance(kind, ast.ForStatement):
            if isinstance(kind.values.ty.kind, types.ArrayType):
                kind.variable.ty = kind.values.ty.kind.element_type
            else:
                self.error(kind.values.location,
                           f'Expected array, not {kind.values.ty}')

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)
        self.check_expression(expression)

    def check_expression(self, expression: ast.Expression):
        """ Perform type checking on expression! """
        kind = expression.kind
        if isinstance(kind, (ast.NumericConstant, ast.StringConstant, ast.BoolLiteral)):
            pass
        elif isinstance(kind, ast.ArrayLiteral):
            assert len(kind.values) > 0
            expression.ty = types.array_type(
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
            if kind.base.ty.has_field(kind.field):
                expression.ty = kind.base.ty.get_field_type(
                    kind.field)
            else:
                self.error(expression.location,
                           f'{kind.base.ty} has no field: {kind.field}')
                expression.ty = void_type

        elif isinstance(kind, ast.ArrayIndex):
            if isinstance(kind.base.ty.kind, types.ArrayType):
                expression.ty = kind.base.ty.kind.element_type
            else:
                self.error(expression.location,
                           f"Indexing requires array type, not {kind.base.ty}")

        elif isinstance(kind, ast.FunctionCall):
            if isinstance(kind.target.ty.kind, types.FunctionType):
                self.check_arguments(
                    kind.target.ty.kind.parameter_types, kind.args, expression.location)
                expression.ty = kind.target.ty.kind.return_type
            elif isinstance(kind.target.ty.kind, types.ClassType):
                # Assume constructor is called without arguments for now
                # TODO: allow constructors!
                self.check_arguments([], kind.args, expression.location)
                expression.ty = kind.target.ty
            else:
                self.error(expression.location,
                           f'Trying to call non-function type: {kind.target.ty}')

        elif isinstance(kind, ast.NewOp):
            raise ValueError("Must be rewritten before!")
        elif isinstance(kind, ast.NameRef):
            raise ValueError(f"Must be resolved: {kind}")
        elif isinstance(kind, ast.StructLiteral):
            assert len(kind.ty.kind.struct_def.fields) == len(kind.values)
            for field, value in zip(kind.ty.kind.struct_def.fields, kind.values):
                self.assert_type(value, field.ty)
            expression.ty = kind.ty
        elif isinstance(kind, ast.EnumLiteral):
            self.check_arguments(kind.variant.payload,
                                 kind.values, expression.location)
            # TODO: is this correct?
            type_arguments = []
            expression.ty = kind.enum_def.get_type(type_arguments)
        elif isinstance(kind, ast.ObjRef):
            obj = kind.obj
            if isinstance(obj, ast.Variable):
                expression.ty = obj.ty
            elif isinstance(obj, ast.BuiltinFunction):
                expression.ty = obj.ty
            elif isinstance(obj, ast.FunctionDef):
                expression.ty = obj.get_type()
            elif isinstance(obj, ast.Parameter):
                expression.ty = obj.ty
            elif isinstance(obj, ast.ClassDef):
                expression.ty = obj.get_type([])
            else:
                raise NotImplementedError(str(kind))
        else:
            raise NotImplementedError(str(expression.kind))

    def check_arguments(self, types: list[types.MyType], values: list[ast.Expression], location: Location):
        """ Check amount and types a list of values """
        if len(values) == len(types):
            for arg, expected_ty in zip(values, types):
                self.assert_type(arg, expected_ty)
        else:
            self.error(
                location, f'Got {len(values)} arguments, expected {len(types)}')

    def assert_type(self, expression: ast.Expression, ty: types.MyType):
        """ Check if expression is of given type, raise error otherwise.
        """
        # Try to auto-convert before check
        if expression.ty.is_int() and ty.is_float():
            # Auto-conv int to floats
            old_expr = expression.clone()
            expression.kind = ast.TypeCast(ty, old_expr)
            expression.ty = ty

        if not expression.ty.equals(ty):
            self.error(
                expression.location,
                f"Got {expression.ty}, expected {ty}"
            )
