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
        if isinstance(expression.kind, ast.TypeLiteral):
            return expression.kind.ty
        elif isinstance(expression.kind, ast.GenericLiteral):
            return expression.kind.tycon.apply2()
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
            if isinstance(kind.base.kind, ast.TypeLiteral):
                ty = kind.base.kind.ty
            elif isinstance(kind.base.kind, ast.GenericLiteral):
                ty = kind.base.kind.tycon.apply2()
            else:
                ty = None

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
                expression.kind = ast.EnumLiteral(
                    kind.target.kind.enum_ty, kind.target.kind.variant, kind.args
                )
            elif isinstance(kind.target.kind, ast.GenericLiteral):
                ty = kind.target.kind.tycon.apply2()
                if ty.is_class():
                    expression.kind = ast.ClassLiteral(ty)

        elif isinstance(kind, ast.ObjRef):
            obj = kind.obj
            if isinstance(obj, ast.TypeConstructor):
                expression.kind = ast.GenericLiteral(obj)
            elif isinstance(obj, ast.MyType):
                expression.kind = ast.TypeLiteral(obj)
            elif isinstance(obj, ast.TypeVar):
                expression.kind = ast.TypeLiteral(ast.type_var_ref(obj))

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
        kind = expression.kind

        if isinstance(kind, ast.NewOp):
            # Fixup new-op operation

            named_values = {}
            for label_value in kind.fields:
                if label_value.name in named_values:
                    self.error(
                        label_value.location, f"Duplicate field: {label_value.name}"
                    )
                else:
                    named_values[label_value.name] = label_value

            expression.ty = kind.new_ty
            ty = expand(kind.new_ty)
            if ty.is_struct():
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

            else:
                self.error(
                    expression.location,
                    f"Can only contrap struct type, not {kind.new_ty}",
                )
