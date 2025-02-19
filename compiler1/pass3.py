"""Additional pass collection, somewhere during analysis. Roughly pass3...

TODO: figure out better name.
"""

from . import ast
from .location import Location
from .basepass import BasePass


def evaluate_types(module: ast.Module):
    TypeEvaluation().run(module)
    NewOpPass().run(module)


class TypeEvaluation(BasePass):
    """Evaluate type expressions."""

    name = "type-evaluator"

    def visit_type(self, ty: ast.Type):
        super().visit_type(ty)

        if isinstance(ty.kind, ast.UnApp):
            ty.change_to(ty.kind.tycon.apply2())

    def tycon_apply(
        self,
        location: Location,
        tycon: ast.TypeConstructor,
        type_arguments: list[ast.Type],
    ) -> ast.Type:
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
                # TODO: check if we can omit type arguments.
                # Omitting type arguments relaxes the requirements on types you must provide. It's noice.
                ty = obj.apply2()
                expression.kind = ast.TypeLiteral(ty)

            elif isinstance(obj, ast.Type):
                expression.kind = ast.TypeLiteral(obj)
            elif isinstance(obj, ast.TypeParameter):
                expression.kind = ast.TypeLiteral(ast.type_parameter_ref(obj))


class NewOpPass(BasePass):
    """Translate object initializers to struct literals."""

    name = "new-op"

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)

        if isinstance(expression.kind, ast.FunctionCall):
            # Fixup new-op operation

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
                elif ty.is_float() or ty.is_int():
                    value = expression.kind.args[0].value
                    expression.kind = ast.TypeCast(ty, value)
                elif ty.is_str():
                    value = expression.kind.args[0].value
                    expression.kind = ast.ToString(value)
                else:
                    self.error(
                        expression.location,
                        f"Can only contrap struct type, not {ty}",
                    )


def try_as_type(expression: ast.Expression):
    if isinstance(expression.kind, ast.TypeLiteral):
        return expression.kind.ty
