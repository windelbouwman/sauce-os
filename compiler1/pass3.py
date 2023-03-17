""" Additional pass collection, somewhere during analysis. Roughly pass3...

TODO: figure out better name.
"""

import logging
from . import ast, types
from .basepass import BasePass

logger = logging.getLogger('pass3')


class TypeEvaluation(BasePass):
    """ Evaluate type expressions.
    """

    def run(self, module: ast.Module):
        self.begin(module.filename, f"Evaluating types in '{module.name}'")
        self.visit_module(module)
        self.finish("Types evaluated")

    def visit_type(self, ty: types.MyType):
        super().visit_type(ty)
        if isinstance(ty.kind, types.TypeExpression):
            ty.kind = self.eval_type_expr(ty.kind.expr).kind

    def eval_type_expr(self, expression: ast.Expression) -> types.MyType:
        # TBD: combine this with name binding?
        if isinstance(expression.kind, ast.ObjRef):
            obj = expression.kind.obj
            if isinstance(obj, types.MyType):
                return obj
            elif isinstance(obj, ast.StructDef):
                return types.struct_type(obj, [])
            elif isinstance(obj, ast.EnumDef):
                return types.enum_type(obj, [])
            elif isinstance(obj, ast.ClassDef):
                return types.class_type(obj, [])
            elif isinstance(obj, ast.TypeDef):
                raise NotImplementedError("TODO: type-def")
                # return obj.ty
            elif isinstance(obj, ast.TypeVar):
                return types.type_var_ref(obj)
            else:
                self.error(expression.location,
                           f'No type object: {obj}')
                return types.void_type
        elif isinstance(expression.kind, ast.ArrayIndex):
            type_arguments = [
                self.eval_type_expr(a) for a in [expression.kind.index]]
            generic = self.eval_generic_expr(expression.kind.base)
            if generic:
                return generic.get_type(type_arguments)
            else:
                return types.void_type
        else:
            self.error(expression.location,
                       f'Invalid type expression: {expression.kind}')
            return types.void_type

    def eval_generic_expr(self, expression: ast.Expression):
        """ Evaluate expression when used as generic """
        if isinstance(expression.kind, ast.ObjRef):
            obj = expression.kind.obj
            if isinstance(obj, (ast.StructDef, ast.EnumDef, ast.ClassDef)):
                return obj
        self.error(expression.location, f'Invalid generic')


class NewOpPass(BasePass):
    """ Translate object initializers to struct literals."""

    def run(self, module: ast.Module):
        self.begin(module.filename, f"Resolving new-ops '{module.name}'")
        self.visit_module(module)
        self.finish("New-ops resolved")

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
            if kind.new_ty.is_struct():
                values = []
                for name in kind.new_ty.get_field_names():
                    if name in named_values:
                        values.append(named_values.pop(name).value)
                    else:
                        self.error(expression.location,
                                   f"Missing field {name}")

                for left in named_values.values():
                    self.error(left.location,
                               f"Superfluous field: {left.name}")
                expression.kind = ast.StructLiteral(kind.new_ty, values)
                expression.ty = kind.new_ty

            else:
                self.error(
                    expression.location, f'Can only contrap struct type, not {kind.new_ty}')
