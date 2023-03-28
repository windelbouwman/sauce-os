""" Additional pass collection, somewhere during analysis. Roughly pass3...

TODO: figure out better name.
"""

import logging
from . import ast
from .basepass import BasePass
from .typechecker import expand

logger = logging.getLogger('pass3')


class TypeEvaluation(BasePass):
    """ Evaluate type expressions.
    """
    name = 'type-evaluator'

    def visit_type(self, ty: ast.MyType):
        super().visit_type(ty)
        if isinstance(ty.kind, ast.TypeExpression):
            ty.kind = self.eval_type_expr(ty.kind.expr).kind

    def eval_type_expr(self, expression: ast.Expression) -> ast.MyType:
        """ Evaluate a type expression.
        """
        if isinstance(expression.kind, ast.ObjRef):
            obj = expression.kind.obj
            if isinstance(obj, ast.MyType):
                return obj
            elif isinstance(obj, ast.StructDef):
                return ast.struct_type(obj, [])
            elif isinstance(obj, ast.EnumDef):
                return ast.enum_type(obj, [])
            elif isinstance(obj, ast.ClassDef):
                return ast.class_type(obj, [])
            elif isinstance(obj, ast.TypeDef):
                raise NotImplementedError("TODO: type-def")
                # return obj.ty
            elif isinstance(obj, ast.TypeVar):
                return ast.type_var_ref(obj)
            else:
                self.error(expression.location,
                           f'No type object: {obj}')
                return ast.void_type
        elif isinstance(expression.kind, ast.ArrayIndex):
            type_arguments = [
                self.eval_type_expr(a) for a in [expression.kind.index]]
            generic = self.eval_generic_expr(expression.kind.base)
            if generic:
                return ast.tycon_apply(generic, type_arguments)
                # return generic.get_type(type_arguments)
            else:
                return ast.void_type
        else:
            self.error(expression.location,
                       f'Invalid type expression: {expression.kind}')
            return ast.void_type

    def eval_generic_expr(self, expression: ast.Expression) -> ast.TypeConstructor:
        """ Evaluate expression when used as generic """
        if isinstance(expression.kind, ast.ObjRef):
            obj = expression.kind.obj
            if isinstance(obj, ast.StructDef):
                return obj
            elif isinstance(obj, ast.EnumDef):
                return obj
            elif isinstance(obj, ast.ClassDef):
                return obj
        self.error(expression.location, f'Invalid generic')


class NewOpPass(BasePass):
    """ Translate object initializers to struct literals."""

    name = 'new-op'

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)
        kind = expression.kind

        if isinstance(kind, ast.NewOp):
            # Fixup new-op operation

            named_values = {}
            for label_value in kind.fields:
                if label_value.name in named_values:
                    self.error(label_value.location,
                               f"Duplicate field: {label_value.name}")
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
                        self.error(expression.location,
                                   f"Missing field {name}")

                for left in named_values.values():
                    self.error(left.location,
                               f"Superfluous field: {left.name}")
                expression.kind = ast.StructLiteral(ty, values)
                expression.ty = ty

            else:
                self.error(
                    expression.location, f'Can only contrap struct type, not {kind.new_ty}')
