

import logging
from . import ast, types
from .location import Location

from .symboltable import Scope
from .basepass import BasePass

logger = logging.getLogger('namebinding')


def base_scope() -> Scope:
    top_scope = Scope()
    top_scope.define('std', ast.BuiltinModule(
        'std', {
            'print': ast.BuiltinFunction('std_print', [types.str_type], types.void_type),
            'int_to_str': ast.BuiltinFunction('std_int_to_str', [types.int_type], types.str_type),
        }))
    top_scope.define('str', types.str_type)
    top_scope.define('int', types.int_type)
    top_scope.define('float', types.float_type)
    return top_scope


class ScopeFiller(BasePass):
    def __init__(self, code: str):
        super().__init__(code)
        self._scopes: list[Scope] = []

    def fill_module(self, module: ast.Module):
        logger.info("Filling scopes")
        self.enter_scope()
        self.visit_module(module)
        module.scope = self.leave_scope()

    def visit_definition(self, definition: ast.Definition):
        if isinstance(definition, ast.StructDef):
            self.define_symbol(definition.name, definition)
            self.enter_scope()
            for field in definition.fields:
                self.define_symbol(field.name, field)
        elif isinstance(definition, ast.FunctionDef):
            self.define_symbol(definition.name, definition)
            self.enter_scope()
            for parameter in definition.parameters:
                self.define_symbol(parameter.name, parameter)
        else:
            raise NotImplementedError(str(ty))

        super().visit_definition(definition)
        definition.scope = self.leave_scope()

    def visit_statement(self, statement: ast.Statement):
        super().visit_statement(statement)
        if isinstance(statement.kind, ast.LetStatement):
            variable = ast.Variable(statement.kind.target, types.void_type)
            statement.kind.variable = variable
            self.define_symbol(statement.kind.target, variable)
        elif isinstance(statement.kind, ast.ForStatement):
            variable = ast.Variable(statement.kind.target, types.void_type)
            statement.kind.variable = variable
            self.define_symbol(statement.kind.target, variable)

    def enter_scope(self):
        scope = Scope()
        self._scopes.append(scope)

    def leave_scope(self) -> Scope:
        return self._scopes.pop()

    def define_symbol(self, name: str, symbol):
        assert isinstance(name, str)
        logger.debug(f"Define name '{name}'")
        scope = self._scopes[-1]
        if scope.is_defined(name):
            self.error(symbol.location, f'{name} is already defined')
        else:
            scope.define(name, symbol)


class NameBinder(BasePass):
    """ Use filled scopes to bind symbols.
    """

    def __init__(self, code: str):
        super().__init__(code)
        self._scopes = [base_scope()]

    def resolve_symbols(self, module: ast.Module):
        logger.info("Resolving symbols")
        self.enter_scope(module.scope)
        for imp in module.imports:
            self.check_name(imp.name, imp.location)

        self.visit_module(module)
        self.leave_scope()

    def visit_definition(self, definition: ast.Definition):
        if isinstance(definition, ast.FunctionDef):
            scope: Scope = definition.scope
        else:
            scope = None

        if scope:
            self.enter_scope(scope)
        super().visit_definition(definition)
        if scope:
            self.leave_scope()

        if isinstance(definition, ast.FunctionDef):
            for parameter in definition.parameters:
                if isinstance(parameter.ty, types.TypeExpression):
                    parameter.ty = self.eval_type_expr(parameter.ty.expr)
            if isinstance(definition.return_ty, types.TypeExpression):
                definition.return_ty = self.eval_type_expr(
                    definition.return_ty.expr)
        elif isinstance(definition, ast.StructDef):
            for field in definition.fields:
                if isinstance(field.ty, types.TypeExpression):
                    field.ty = self.eval_type_expr(field.ty.expr)

    def eval_type_expr(self, expression: ast.Expression) -> types.MyType:
        # TBD: combine this with name binding?
        if isinstance(expression.kind, ast.ObjRef):
            obj = expression.kind.obj
            if isinstance(obj, types.MyType):
                return obj
            elif isinstance(obj, ast.StructDef):
                return types.StructType(obj)
            else:
                self.error(expression.location,
                           f'No type object: {obj}')
                return types.void_type
        else:
            self.error(expression.location,
                       f'Invalid type expression: {expression.kind}')
            return types.void_type

    def visit_statement(self, statement: ast.Statement):
        super().visit_statement(statement)
        kind = statement.kind
        if isinstance(kind, ast.LetStatement):
            if kind.ty:
                if isinstance(kind.ty, types.TypeExpression):
                    kind.ty = self.eval_type_expr(kind.ty.expr)

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, ast.NameRef):
            obj = self.check_name(kind.name, expression.location)
            expression.kind = ast.ObjRef(obj)
        elif isinstance(kind, ast.DotOperator):
            # Resolve obj_ref . field at this point, we can do this here.
            if isinstance(kind.base.kind, ast.ObjRef):
                obj = kind.base.kind.obj
                if isinstance(obj, ast.BuiltinModule):
                    expression.kind = ast.ObjRef(obj.symbols[kind.field])
        elif isinstance(kind, ast.NewOp):
            # Fixup new-op operation
            if isinstance(kind.new_ty, types.TypeExpression):
                kind.new_ty = self.eval_type_expr(kind.new_ty.expr)

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
                for field in kind.new_ty.struct_def.fields:
                    if field.name in named_values:
                        values.append(named_values.pop(field.name).value)
                    else:
                        self.error(expression.location,
                                   f"Missing field {field.name}")

                for left in named_values.values():
                    self.error(left.location,
                               f"Superfluous field: {left.name}")
                expression.kind = ast.StructLiteral(kind.new_ty, values)
                expression.ty = kind.new_ty

            else:
                self.error(
                    expression.location, f'Can only contrap struct type, not {kind.new_ty}')
            # Check that all fields are filled!

    def enter_scope(self, scope: Scope):
        self._scopes.append(scope)

    def leave_scope(self):
        self._scopes.pop()

    def check_name(self, name: str, location: Location):
        assert isinstance(name, str), str(type(name))
        scope = self._scopes[-1]
        for scope in reversed(self._scopes):
            if scope.is_defined(name):
                obj = scope.lookup(name)
                assert obj
                return obj

        self.error(location, f'Undefined symbol: {name}')
        return ast.Undefined()
