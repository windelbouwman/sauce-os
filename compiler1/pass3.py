""" Additional pass collection, somewhere during analysis. Roughly pass3...

TODO: figure out better name.
"""

import logging
from . import ast
from .location import Location
from .basepass import BasePass
from .typechecker import expand

logger = logging.getLogger("pass3")


class TypeEvaluation(BasePass):
    """Evaluate type expressions."""

    name = "type-evaluator"

    def visit_type(self, ty: ast.MyType):
        super().visit_type(ty)
        if isinstance(ty.kind, ast.TypeExpression):
            ty.change_to(self.eval_type_expr(ty.kind.expr))

    def eval_type_expr(self, expression: ast.Expression) -> ast.MyType:
        """Evaluate a type expression."""
        ty = try_as_type(expression)
        if ty:
            return ty
        else:
            self.error(
                expression.location, f"Invalid type expression: {expression.kind}"
            )
            return ast.void_type

    def tycon_apply(
        self,
        location: Location,
        tycon: ast.TypeConstructor,
        type_arguments: list[ast.MyType],
    ) -> ast.MyType:
        if len(tycon.type_parameters) == len(type_arguments):
            return tycon.apply(type_arguments)
        else:
            self.error(
                location,
                f"Expected {len(tycon.type_parameters)} type arguments, got {len(type_arguments)}",
            )
            return ast.void_type

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)
        kind = expression.kind

        if isinstance(kind, ast.DotOperator):
            # Resolve obj_ref . field at this point, we can do this here.
            ty = try_as_type(kind.base)

            if ty and ty.is_enum():
                if ty.has_variant(kind.field):
                    variant = ty.get_variant(kind.field)
                    expression.kind = ast.SemiEnumLiteral(ty, variant)
                else:
                    self.error(
                        expression.location, f"No such enum variant: {kind.field}"
                    )

        elif isinstance(kind, ast.FunctionCall):
            if isinstance(kind.target.kind, ast.SemiEnumLiteral):
                values = [a.value for a in kind.args]
                expression.kind = ast.EnumLiteral(
                    kind.target.kind.enum_ty, kind.target.kind.variant, values
                )
            else:
                ty = try_as_type(kind.target)
                if ty:
                    if ty.is_class():
                        expression.kind = ast.ClassLiteral(ty, kind.args)

        elif isinstance(kind, ast.ObjRef):
            obj = kind.obj
            if isinstance(obj, ast.TypeConstructor):
                expression.kind = ast.GenericLiteral(obj)
            elif isinstance(obj, ast.MyType):
                expression.kind = ast.TypeLiteral(obj)
            elif isinstance(obj, ast.TypeParameter):
                expression.kind = ast.TypeLiteral(ast.type_parameter_ref(obj))

        elif isinstance(kind, ast.ArrayIndex):
            if isinstance(kind.base.kind, ast.GenericLiteral):
                tycon = kind.base.kind.tycon
                type_arguments = [self.eval_type_expr(index) for index in kind.indici]
                ty = self.tycon_apply(expression.location, tycon, type_arguments)
                expression.kind = ast.TypeLiteral(ty)


class NewOpPass(BasePass):
    """Translate object initializers to struct literals."""

    name = "new-op"

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)

        if isinstance(expression.kind, ast.FunctionCall):
            # Fixup new-op operation

            #  = kind.new_ty
            ty = try_as_type(expression.kind.target)

            if ty:
                if ty.is_struct():
                    expression.ty = ty
                    named_values = {}
                    for label_value in expression.kind.args:
                        if label_value.name in named_values:
                            self.error(
                                label_value.location,
                                f"Duplicate field: {label_value.name}",
                            )
                        else:
                            named_values[label_value.name] = label_value

                    values = []
                    for name in ty.get_field_names():
                        if name in named_values:
                            values.append(named_values.pop(name).value)
                        else:
                            self.error(expression.location, f"Missing field '{name}'")

                    for left in named_values.values():
                        self.error(left.location, f"Superfluous field: {left.name}")
                    expression.kind = ast.StructLiteral(ty, values)
                    expression.ty = ty

                elif ty.is_float():
                    value = expression.kind.args[0].value
                    expression.kind = ast.TypeCast(ty, value)

                elif ty.is_int():
                    value = expression.kind.args[0].value
                    expression.kind = ast.TypeCast(ty, value)

                else:
                    self.error(
                        expression.location,
                        f"Can only contrap struct type, not {ty}",
                    )


def try_as_type(expression: ast.Expression):
    if isinstance(expression.kind, ast.TypeLiteral):
        ty = expression.kind.ty
    elif isinstance(expression.kind, ast.GenericLiteral):
        # TODO: check if we can omit type arguments.
        # Omitting type arguments relaxes the requirements on types you must provide. It's noice.
        # if len(expression.kind.tycon.type_parameters) == 0:
        ty = expression.kind.tycon.apply2()
        # else:
        #    ty = None
    elif isinstance(expression.kind, ast.ArrayLiteral):
        if len(expression.kind.values) == 1:
            element_type = try_as_type(expression.kind.values[0])
            if element_type:
                ty = ast.array_type(None, element_type)
            else:
                ty = None
        else:
            ty = None
    else:
        ty = None
    return ty
