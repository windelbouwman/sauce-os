""" Type checker.
"""


import logging

from . import ast
from .basepass import BasePass
from .location import Location
from .ast import bool_type, void_type

logger = logging.getLogger('typechecker')


class TypeChecker(BasePass):
    def __init__(self):
        super().__init__()
        self._function = None

    def check_module(self, module: ast.Module):
        self.begin(module.filename, f"Type checking module '{module.name}'")
        self.visit_module(module)
        self.finish("Type check OK.")

    def visit_definition(self, definition: ast.Definition):
        if isinstance(definition, ast.FunctionDef):
            logger.debug(f"Checking function '{definition.name}'")
            assert not self._function
            self._function = definition

        super().visit_definition(definition)

        if isinstance(definition, (ast.StructDef, ast.EnumDef, ast.TypeDef)):
            pass
        elif isinstance(definition, ast.FunctionDef):
            self._function = None
        elif isinstance(definition, ast.ClassDef):
            pass
        elif isinstance(definition, ast.VarDef):
            self.assert_type(definition.value, definition.ty)
        else:
            raise NotImplementedError(str(definition))

    def visit_statement(self, statement: ast.Statement):
        kind = statement.kind

        # Handle special cases:
        if isinstance(kind, ast.CaseStatement):
            self.visit_expression(kind.value)
            if kind.value.ty.is_enum():
                variant_names = kind.value.ty.get_variant_names()
                for arm in kind.arms:
                    if kind.value.ty.has_variant(arm.name):
                        variant_names.remove(arm.name)
                        variant = kind.value.ty.get_variant(arm.name)
                        payload_types = kind.value.ty.get_variant_types(
                            arm.name)

                        # HACK to pass variant to transform pass:
                        arm.variant = variant

                        if len(payload_types) == len(arm.variables):
                            for v, t in zip(arm.variables, payload_types):
                                v.ty = t
                        else:
                            self.error(
                                arm.location, f"Expected {len(payload_types)} variables, got {len(arm.variables)}")
                        # TODO: check missing fields
                    else:
                        self.error(arm.location,
                                   f'No enum variant {arm.name}')
                if variant_names and not kind.else_clause:
                    self.error(statement.location,
                               f'Cases {variant_names} not covered')
            else:
                self.error(kind.value.location,
                           f'Expected enum, not {kind.value.ty}')

            for arm in kind.arms:
                self.visit_node(arm)
        elif isinstance(kind, ast.ForStatement):
            self.visit_expression(kind.values)
            if kind.values.ty.is_array():
                kind.variable.ty = kind.values.ty.kind.element_type
            elif kind.values.ty.has_field('iter'):
                # If it quacks lite an iterator... it must be an iterator!
                iter_ty: ast.MyType = kind.values.ty.get_field_type(
                    'iter').kind.return_type
                opt_ty: ast.MyType = iter_ty.get_field_type(
                    'next').kind.return_type
                val_ty = opt_ty.get_variant_types('Some')[0]
                kind.variable.ty = val_ty
            else:
                self.error(kind.values.location,
                           f'Expected array or iterable, not {kind.values.ty}')
            self.visit_statement(kind.inner)
        else:
            super().visit_statement(statement)

        if isinstance(kind, ast.LoopStatement):
            pass
        elif isinstance(kind, ast.WhileStatement):
            self.assert_type(kind.condition, bool_type)
        elif isinstance(kind, ast.IfStatement):
            self.assert_type(kind.condition, bool_type)
        elif isinstance(kind, ast.SwitchStatement):
            self.assert_type(kind.value, ast.int_type)
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
                if not self.unify(kind.value.ty, self._function.return_ty):
                    self.error(
                        statement.location, f"Returning wrong type {kind.value.ty} (should be {self._function.return_ty})")

        elif isinstance(kind, ast.LetStatement):
            if kind.ty:
                self.assert_type(kind.value, kind.ty)
                kind.variable.ty = kind.ty
            else:
                kind.variable.ty = kind.value.ty.clone()
        elif isinstance(kind, ast.AssignmentStatement):
            self.assert_type(kind.value, kind.target.ty)
        elif isinstance(kind, (ast.ForStatement, ast.CaseStatement)):
            pass  # handled above
        else:
            raise NotImplementedError(str(statement))

    def visit_expression(self, expression: ast.Expression):
        """ Perform type checking on expression! """
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, (ast.NumericConstant, ast.StringConstant, ast.BoolLiteral)):
            pass
        elif isinstance(kind, ast.ArrayLiteral):
            assert len(kind.values) > 0
            expression.ty = ast.array_type(
                len(kind.values), kind.values[0].ty)
        elif isinstance(kind, ast.Binop):
            # Introduce some heuristics...
            if kind.op == '/':
                ty = ast.float_type
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
            if isinstance(kind.base.ty.kind, ast.ArrayType):
                expression.ty = kind.base.ty.kind.element_type
            else:
                self.error(expression.location,
                           f"Indexing requires array type, not {kind.base.ty}")

        elif isinstance(kind, ast.FunctionCall):
            if isinstance(kind.target.ty.kind, ast.FunctionType):
                arg_types = kind.target.ty.kind.parameter_types
                return_type = kind.target.ty.kind.return_type
                self.check_arguments(
                    arg_types, kind.args, expression.location)
                expression.ty = return_type
            elif kind.target.ty.is_class():
                # Assume constructor is called without arguments for now
                # TODO: allow constructors!
                self.check_arguments([], kind.args, expression.location)
                expression.ty = kind.target.ty
            else:
                self.error(expression.location,
                           f'Trying to call non-function type: {kind.target.ty}')

        elif isinstance(kind, ast.NewOp):
            raise ValueError("new-op must be rewritten before!")
        elif isinstance(kind, ast.NameRef):
            raise ValueError(f"Must be resolved: {kind}")
        elif isinstance(kind, ast.StructLiteral):
            field_types = kind.ty.get_field_types()
            assert len(field_types) == len(kind.values)
            for field_type, value in zip(field_types, kind.values):
                self.assert_type(value, field_type)
            expression.ty = kind.ty
        elif isinstance(kind, ast.UnionLiteral):
            field_type = kind.ty.get_field_type(kind.field)
            self.assert_type(kind.value, field_type)
            expression.ty = kind.ty
        elif isinstance(kind, ast.EnumLiteral):
            payload_types = kind.enum_ty.get_variant_types(kind.variant.name)
            self.check_arguments(payload_types,
                                 kind.values, expression.location)
            expression.ty = kind.enum_ty
        elif isinstance(kind, ast.ClassLiteral):
            expression.ty = kind.class_ty
        elif isinstance(kind, ast.TypeLiteral):
            self.error(expression.location, 'Unexpected type')
        elif isinstance(kind, ast.GenericLiteral):
            self.error(expression.location, 'Unexpected generic')
        elif isinstance(kind, ast.ObjRef):
            obj = kind.obj
            if isinstance(obj, ast.Variable):
                expression.ty = obj.ty.clone()
            elif isinstance(obj, ast.BuiltinFunction):
                expression.ty = obj.ty
            elif isinstance(obj, ast.FunctionDef):
                expression.ty = obj.get_type()
            elif isinstance(obj, ast.Parameter):
                expression.ty = obj.ty.clone()
            elif isinstance(obj, ast.ClassDef):
                # Arg, type arguments?
                expression.ty = obj.get_type([])
            else:
                raise NotImplementedError(str(kind))
        elif isinstance(kind, ast.TypeCast):
            expression.ty = kind.ty
        else:
            raise NotImplementedError(str(expression.kind))

    def check_arguments(self, types: list[ast.MyType], values: list[ast.Expression], location: Location):
        """ Check amount and types a list of values """
        if len(values) == len(types):
            for arg, expected_ty in zip(values, types):
                self.assert_type(arg, expected_ty)
        else:
            self.error(
                location, f'Got {len(values)} arguments, expected {len(types)}')

    def assert_type(self, expression: ast.Expression, ty: ast.MyType):
        """ Check if expression is of given type, raise error otherwise.
        """

        # Try to auto-convert before check:
        if expression.ty.is_int() and ty.is_float():
            # Auto-conv int to floats
            old_expr = expression.clone()
            expression.kind = ast.TypeCast(ty, old_expr)
            expression.ty = ty

        if not self.unify(expression.ty, ty):
            self.error(expression.location,
                       f'Expected {ast.str_ty(ty)}, got {ast.str_ty(expression.ty)}')

    def unify(self, a: ast.MyType, b: ast.MyType) -> bool:
        """ Unify types a and b.
        """
        if isinstance(a.kind, ast.App) and isinstance(b.kind, ast.App):
            # Check equal tycon:
            if not a.kind.tycon.equals(b.kind.tycon):
                return False

            # Check equal type_args:
            if len(a.kind.type_args) == len(b.kind.type_args):
                return all(self.unify(u, v) for u, v in zip(a.kind.type_args, b.kind.type_args))
            else:
                return False
        elif isinstance(a.kind, ast.BaseType) and isinstance(b.kind, ast.BaseType):
            return a.kind.equals(b.kind)
        elif isinstance(a.kind, ast.VoidType) and isinstance(b.kind, ast.VoidType):
            return True
        elif isinstance(a.kind, ast.TypeVarKind) and isinstance(b.kind, ast.TypeVarKind):
            return a.kind.type_variable is b.kind.type_variable
        elif isinstance(a.kind, ast.FunctionType) and isinstance(b.kind, ast.FunctionType):
            if not self.unify(a.kind.return_type, b.kind.return_type):
                return False
            if len(a.kind.parameter_types) != len(b.kind.parameter_types):
                return False
            return all(self.unify(u, v) for u, v in zip(a.kind.parameter_types, b.kind.parameter_types))
        elif isinstance(a.kind, ast.Meta):
            if a.kind.assigned:
                assigned = a.kind.assigned
                if self.unify(assigned, b):
                    # Patch type:
                    a.kind = assigned.kind
                    return True
                else:
                    return False
            elif isinstance(b.kind, ast.Meta):
                if a.kind is b.kind:
                    return True
                else:
                    return False
            elif b.is_struct() or b.is_class() or b.is_type_var_ref() or b.is_void() or b.is_enum():
                # TODO: check if b contains meta-var
                # Assign type to meta-var:
                a.kind.assigned = b
                # Patch type:
                a.kind = b.kind
                return True
            else:
                raise NotImplementedError(str(a) + str(b))
                # if isinstance(b.kind, )
                return True
        elif isinstance(b.kind, ast.Meta):
            # Simply swap comparison
            return self.unify(b, a)
        else:
            # location = Location(1, 1)
            # self.error(location, f'Cannot unify types {a} and {b}')
            print('Full nack', a, b)
            return False


def expand(t: ast.MyType) -> ast.MyType:
    if isinstance(t.kind, ast.App) and isinstance(t.kind.tycon, ast.TypeFunc):
        assert len(t.kind.tycon.type_parameters) == len(t.kind.type_args)
        m = dict(zip(t.kind.tycon.type_parameters, t.kind.type_args))
        return expand(subst(t.kind.tycon.ty, m))
    else:
        return t
