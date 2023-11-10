""" Fill scopes with symbols and resolve names using these filled scopes.
"""

import logging
from . import ast
from .location import Location
from .basepass import BasePass

logger = logging.getLogger("namebinding")


def base_scope() -> ast.Scope:
    top_scope = ast.Scope()
    top_scope.define("str", ast.str_type)
    top_scope.define("char", ast.char_type)
    top_scope.define("int", ast.int_type)
    top_scope.define("float", ast.float_type)
    top_scope.define("bool", ast.bool_type)
    return top_scope


class ScopeFiller(BasePass):
    def __init__(self, modules: dict[str, ast.Module]):
        super().__init__()
        self._scopes: list[ast.Scope] = []
        self._modules = modules

    def fill_module(self, module: ast.Module):
        self.begin(module.filename, f"Filling scopes in module '{module.name}'")

        if module.name in self._modules:
            self.error(module.location, f"Cannot redefine {module.name}")
        else:
            self._modules[module.name] = module

        self.enter_scope(module.scope)
        for imp in module.imports:
            if imp.modname in self._modules:
                mod = self._modules[imp.modname]
                if isinstance(imp, ast.Import):
                    self.define_symbol(imp.modname, mod)
                elif isinstance(imp, ast.ImportFrom):
                    for name, location in imp.names:
                        if mod.has_field(name):
                            self.define_symbol(name, mod.get_field(name))
                        else:
                            self.error(location, f"No such field: {name}")
                else:
                    raise NotImplementedError(str(imp))
            else:
                self.error(imp.location, f"Module {imp.modname} not found")

        self.visit_module(module)
        self.leave_scope()
        assert not self._scopes
        self.finish("Scopes filled")

    def visit_definition(self, definition: ast.Definition):
        self.define(definition)
        self.enter_scope(definition.scope)
        if isinstance(definition, ast.StructDef):
            for type_parameter in definition.type_parameters:
                self.define(type_parameter)
            for field in definition.fields:
                self.define(field)
        elif isinstance(definition, ast.EnumDef):
            for type_parameter in definition.type_parameters:
                self.define(type_parameter)
            for variant in definition.variants:
                self.define(variant)
        elif isinstance(definition, ast.FunctionDef):
            for type_parameter in definition.type_parameters:
                self.define(type_parameter)
            if definition.this_parameter:
                self.define(definition.this_parameter)
            for parameter in definition.parameters:
                self.define(parameter)
        elif isinstance(definition, ast.ClassDef):
            for type_parameter in definition.type_parameters:
                self.define(type_parameter)
        elif isinstance(definition, (ast.VarDef, ast.TypeDef)):
            pass
        else:
            raise NotImplementedError(str(definition))

        super().visit_definition(definition)
        self.leave_scope()

    def visit_node(self, node: ast.Node):
        if isinstance(node, ast.CaseArm):
            self.enter_scope(node.block.scope)
            has_scope = True
            for variable in node.variables:
                self.define(variable)
        else:
            has_scope = False
        super().visit_node(node)
        if has_scope:
            self.leave_scope()

    def visit_statement(self, statement: ast.Statement):
        kind = statement.kind
        if isinstance(kind, ast.IfStatement):
            self.visit_expression(kind.condition)
            self.visit_scoped_block(kind.true_block)
            self.visit_scoped_block(kind.false_block)

        elif isinstance(kind, ast.WhileStatement):
            self.visit_expression(kind.condition)
            self.visit_scoped_block(kind.block)

        elif isinstance(kind, ast.LoopStatement):
            self.visit_scoped_block(kind.block)

        elif isinstance(kind, ast.ForStatement):
            self.visit_expression(kind.values)
            self.enter_scope(kind.block.scope)
            self.define(kind.variable)
            self.visit_statement(kind.block.body)
            self.leave_scope()

        elif isinstance(kind, ast.TryStatement):
            self.visit_statement(kind.try_block.body)

            self.visit_type(kind.parameter.ty)
            self.enter_scope(kind.except_block.scope)
            self.define(kind.parameter)
            self.visit_statement(kind.except_block.body)
            self.leave_scope()

        else:
            super().visit_statement(statement)

            if isinstance(kind, ast.LetStatement):
                self.define(kind.variable)

    def visit_scoped_block(self, block: ast.ScopedBlock):
        self.enter_scope(block.scope)
        self.visit_statement(block.body)
        self.leave_scope()

    def enter_scope(self, scope: ast.Scope):
        self._scopes.append(scope)

    def leave_scope(self):
        self._scopes.pop()

    def define(self, definition: ast.Definition):
        self.define_symbol(definition.id.name, definition)

    def define_symbol(self, name: str, symbol: ast.Definition):
        assert isinstance(name, str)
        logger.debug(f"Define name '{name}'")
        scope = self._scopes[-1]
        if scope.is_defined(name):
            self.error(symbol.location, f"{name} is already defined")
        else:
            scope.define(name, symbol)


class NameBinder(BasePass):
    """Use filled scopes to bind symbols."""

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
        self.enter_scope(definition.scope)
        super().visit_definition(definition)
        self.leave_scope()

    def visit_statement(self, statement: ast.Statement):
        kind = statement.kind

        if isinstance(kind, ast.IfStatement):
            self.visit_expression(kind.condition)
            self.visit_scoped_block(kind.true_block)
            self.visit_scoped_block(kind.false_block)

        elif isinstance(kind, ast.ForStatement):
            self.visit_expression(kind.values)
            self.visit_scoped_block(kind.block)

        elif isinstance(kind, ast.WhileStatement):
            self.visit_expression(kind.condition)
            self.visit_scoped_block(kind.block)

        elif isinstance(kind, ast.LoopStatement):
            self.visit_scoped_block(kind.block)

        elif isinstance(kind, ast.TryStatement):
            self.visit_scoped_block(kind.try_block)
            self.visit_type(kind.parameter.ty)
            self.visit_scoped_block(kind.except_block)

        else:
            super().visit_statement(statement)

    def visit_scoped_block(self, block: ast.ScopedBlock):
        self.enter_scope(block.scope)
        self.visit_statement(block.body)
        self.leave_scope()

    def visit_node(self, node: ast.Node):
        if isinstance(node, ast.CaseArm):
            scope = node.block.scope
        else:
            scope = None

        if scope:
            self.enter_scope(scope)
        super().visit_node(node)
        if scope:
            self.leave_scope()

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
                if isinstance(obj, ast.Module):
                    if obj.has_field(kind.field):
                        expression.kind = ast.ObjRef(obj.get_field(kind.field))
                    else:
                        self.error(expression.location, f"No such field: {kind.field}")

    def enter_scope(self, scope: ast.Scope):
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
                if scope.this_parameter:
                    # print("class var ref!", name)
                    # return ast.Undefined()
                    return obj
                else:
                    return obj

        self.error(location, f"Undefined symbol: {name}")
        return ast.Undefined()
