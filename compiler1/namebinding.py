

import logging
from . import ast, types
from .location import Location
from .symboltable import Scope
from .basepass import BasePass

logger = logging.getLogger('namebinding')


def base_scope() -> Scope:
    top_scope = Scope()
    top_scope.define('str', types.str_type)
    top_scope.define('int', types.int_type)
    top_scope.define('float', types.float_type)
    top_scope.define('bool', types.bool_type)
    return top_scope


class ScopeFiller(BasePass):
    def __init__(self, modules: dict[str, ast.Module]):
        super().__init__()
        self._scopes: list[Scope] = []
        self._modules = modules

    def fill_module(self, module: ast.Module):
        self.begin(module.filename,
                   f"Filling scopes in module '{module.name}'")
        self.define_module(module)
        self.enter_scope()
        for imp in module.imports:
            if imp.modname in self._modules:
                mod = self._modules[imp.modname]
                if isinstance(imp, ast.Import):
                    self.define_symbol(imp.modname, mod)
                elif isinstance(imp, ast.ImportFrom):
                    for name in imp.names:
                        if mod.has_field(name):
                            self.define_symbol(name, mod.get_field(name))
                        else:
                            self.error(imp.location,
                                       f'No such field: {name}')
                else:
                    raise NotImplementedError(str(imp))
            else:
                self.error(imp.location, f"Module {imp.modname} not found")

        self.visit_module(module)
        module.scope = self.leave_scope()
        self.finish("Scopes filled")

    def define_module(self, module: ast.Module):
        if module.name in self._modules:
            self.error(module.location, f"Cannot redefine {module.name}")
        else:
            self._modules[module.name] = module

    def visit_definition(self, definition: ast.Definition):
        has_scope = False
        if isinstance(definition, ast.StructDef):
            self.define_symbol(definition.name, definition)
            self.enter_scope()
            has_scope = True
            for field in definition.fields:
                self.define_symbol(field.name, field)
        elif isinstance(definition, ast.EnumDef):
            self.define_symbol(definition.name, definition)
            self.enter_scope()
            has_scope = True
            for variant in definition.variants:
                self.define_symbol(variant.name, variant)
        elif isinstance(definition, ast.FunctionDef):
            self.define_symbol(definition.name, definition)
            self.enter_scope()
            has_scope = True
            for parameter in definition.parameters:
                self.define_symbol(parameter.name, parameter)
        elif isinstance(definition, ast.ClassDef):
            self.define_symbol(definition.name, definition)
            self.enter_scope()
            has_scope = True
        elif isinstance(definition, ast.VarDef):
            self.define_symbol(definition.name, definition)
            has_scope = False
        else:
            raise NotImplementedError(str(definition))

        super().visit_definition(definition)
        if has_scope:
            definition.scope = self.leave_scope()

    def visit_node(self, node: ast.Node):
        if isinstance(node, ast.CaseArm):
            self.enter_scope()
            has_scope = True
            for variable in node.variables:
                self.define_symbol(variable.name, variable)
        else:
            has_scope = False
        super().visit_node(node)
        if has_scope:
            node.scope = self.leave_scope()

    def visit_statement(self, statement: ast.Statement):
        super().visit_statement(statement)
        kind = statement.kind
        if isinstance(kind, ast.LetStatement):
            self.define_symbol(kind.variable.name, kind.variable)
        elif isinstance(kind, ast.ForStatement):
            self.define_symbol(kind.variable.name, kind.variable)

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

    def __init__(self):
        super().__init__()
        self._scopes = [base_scope()]

    def resolve_symbols(self, module: ast.Module):
        self.begin(module.filename, f"Resolving symbols in '{module.name}'")
        self.enter_scope(module.scope)

        self.visit_module(module)
        self.leave_scope()
        self.finish("Symbols resolved")

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

    def visit_node(self, node: ast.Node):
        if isinstance(node, ast.CaseArm):
            scope = node.scope
        else:
            scope = None

        if scope:
            self.enter_scope(scope)
        super().visit_node(node)
        if scope:
            self.leave_scope()

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
                return types.struct_type(obj)
            elif isinstance(obj, ast.EnumDef):
                return types.enum_type(obj)
            else:
                self.error(expression.location,
                           f'No type object: {obj}')
                return types.void_type
        elif isinstance(expression.kind, ast.ArrayIndex):
            # TODO: apply generic parameters!
            return expression.kind.base
        else:
            self.error(expression.location,
                       f'Invalid type expression: {expression.kind}')
            return types.void_type

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
                if isinstance(obj, (ast.BuiltinModule, ast.Module)):
                    if obj.has_field(kind.field):
                        expression.kind = ast.ObjRef(obj.get_field(kind.field))
                    else:
                        self.error(expression.location,
                                   f'No such field: {kind.field}')
                elif isinstance(obj, ast.EnumDef):
                    if obj.scope.is_defined(kind.field):
                        variant = obj.scope.lookup(kind.field)
                        expression.kind = ast.SemiEnumLiteral(obj, variant)
                    else:
                        self.error(expression.location,
                                   f"No such enum variant: {kind.field}")

        elif isinstance(kind, ast.FunctionCall):
            if isinstance(kind.target.kind, ast.SemiEnumLiteral):
                expression.kind = ast.EnumLiteral(
                    kind.target.kind.enum_def, kind.target.kind.variant, kind.args)
        elif isinstance(kind, ast.NewOp):
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
                for field in kind.new_ty.kind.struct_def.fields:
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
