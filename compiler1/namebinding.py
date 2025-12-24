"""Fill scopes with symbols and resolve names using these filled scopes."""

import logging
from . import ast
from .location import Location, Span
from .basepass import BasePass
from .errors import ParseError

logger = logging.getLogger("slangc.namebinding")


def resolve_names(known_modules, module: ast.Module):
    """Fill scopes and bind names"""
    ScopeFiller(known_modules).fill_module(module)
    NameBinder().resolve_symbols(module)


def base_scope() -> ast.Scope:
    top_scope = ast.Scope(Span.default())
    top_scope.define("str", ast.str_type)
    top_scope.define("char", ast.char_type)
    top_scope.define("int", ast.int_type)
    top_scope.define("float", ast.float_type)
    top_scope.define("bool", ast.bool_type)

    # Take a short-cut, and assume all integer types are 'int':
    top_scope.define("uint8", ast.int_type)
    top_scope.define("uint16", ast.int_type)
    top_scope.define("uint32", ast.int_type)
    top_scope.define("uint64", ast.int_type)
    top_scope.define("int8", ast.int_type)
    top_scope.define("int16", ast.int_type)
    top_scope.define("int32", ast.int_type)
    top_scope.define("int64", ast.int_type)

    # Take a short-cut, and assume all float types are 'float':
    top_scope.define("float32", ast.float_type)
    top_scope.define("float64", ast.float_type)
    top_scope.define("unreachable", ast.unreachable_type())

    return top_scope


class ScopeFiller(BasePass):
    def __init__(self, modules: dict[str, ast.Module]):
        super().__init__()
        self._scopes: list[ast.Scope] = []
        self._modules = modules
        self._definitions = []

    def fill_module(self, module: ast.Module):
        self._definitions = []
        self.begin(module.filename, f"Filling scopes in module '{module.id.name}'")

        if module.id.name in self._modules:
            self.error(module.location, f"Cannot redefine {module.id.name}")
        else:
            self._modules[module.id.name] = module

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
        module._definitions = self._definitions
        self.finish("Scopes filled")

    def visit_definition(self, definition: ast.Definition):
        self.define(definition)
        if isinstance(definition, ast.ScopedDefinition):
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
            elif isinstance(definition, ast.InterfaceDef):
                for type_parameter in definition.type_parameters:
                    self.define(type_parameter)
            elif isinstance(definition, ast.ImplDef):
                pass
            else:
                raise NotImplementedError(str(definition))

        super().visit_definition(definition)
        if isinstance(definition, ast.ScopedDefinition):
            self.leave_scope()

    def visit_node(self, node: ast.Node):
        if isinstance(node, ast.CaseArm):
            self.enter_scope(node.block.scope)
            has_scope = True
            for variable in node.variables:
                self.define(variable)
        elif isinstance(node, ast.SwitchArm):
            self.enter_scope(node.block.scope)
            has_scope = True
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
        assert isinstance(definition, ast.Definition)
        self._definitions.append((definition.id, definition.location))
        self.define_symbol(definition.id.name, definition)

    def define_symbol(self, name: str, symbol: ast.Definition):
        assert isinstance(name, str)
        assert isinstance(symbol, (ast.Definition, ast.Module))
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
        self._references = []

    def resolve_symbols(self, module: ast.Module):
        self.begin(module.filename, f"Resolving symbols in '{module.id.name}'")
        self._references = []
        self.enter_scope(module.scope)

        self.visit_module(module)
        self.leave_scope()
        module._references = self._references
        self.finish("Symbols resolved")

    def visit_definition(self, definition: ast.Definition):
        if isinstance(definition, ast.ScopedDefinition):
            self.enter_scope(definition.scope)
        super().visit_definition(definition)
        if isinstance(definition, ast.ScopedDefinition):
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
        if isinstance(node, (ast.CaseArm, ast.SwitchArm)):
            scope = node.block.scope
        else:
            scope = None

        if scope:
            self.enter_scope(scope)
        super().visit_node(node)
        if scope:
            self.leave_scope()

    def visit_type(self, ty: ast.Type):
        super().visit_type(ty)
        try:
            if isinstance(ty.kind, ast.NameRefType):
                obj = self.resolve_qual_name(ty.kind.qual_name)
                if isinstance(obj, ast.Type):
                    ty.change_to(obj)
                elif isinstance(obj, ast.TypeConstructor):
                    ty.kind = ast.UnApp(obj)
                elif isinstance(obj, ast.TypeParameter):
                    ty.kind = ast.TypeParameterKind(obj)
                elif isinstance(obj, ast.TypeDef):
                    ty.change_to(obj.ty)
                else:
                    raise ValueError(f"Invalid type: {obj}")
            elif isinstance(ty.kind, ast.AbstractApp):
                obj = self.resolve_qual_name(ty.kind.tycon)
                if isinstance(obj, ast.TypeConstructor):
                    ty.kind = ast.App(obj, ty.kind.type_args)
                else:
                    raise ValueError("Invalid type constructor: {obj}")
        except ParseError as ex:
            self.error(ex.location, ex.message)

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, ast.NameRef):
            expression.kind = self.check_name(kind.name, expression.location)

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
        self._scopes.insert(0, scope)

    def leave_scope(self):
        self._scopes.pop(0)

    def check_name(self, name: str, location: Location) -> ast.ExpressionKind:
        assert isinstance(name, str), str(type(name))
        for scope in self._scopes:
            if scope.is_defined(name):
                obj = scope.lookup(name)
                assert obj
                if hasattr(obj, "id"):
                    self._references.append((obj.id, location))
                if scope.has_this_context:
                    if isinstance(obj, (ast.FunctionDef, ast.VarDef)):
                        this_parameter = self.lookup2("this", location)
                        return ast.DotOperator(this_parameter, name)
                    else:
                        return ast.ObjRef(obj)
                else:
                    return ast.ObjRef(obj)

        self.error(location, f"Undefined symbol: {name}")
        return ast.Undefined()

    def lookup2(self, name: str, location: Location) -> ast.Expression:
        obj = self.lookup(name, location)
        return ast.obj_ref(obj, ast.undefined_type(), location)

    def resolve_qual_name(self, qual_name: ast.QualName):
        sym = self.lookup(qual_name.names[0][1], qual_name.names[0][0])
        for location, attr in qual_name.names[1:]:
            try:
                sym = sym.get_field(attr)
            except ValueError as ex:
                raise ParseError(location, str(ex))
        return sym

    def lookup(self, name: str, location: Location):
        assert isinstance(name, str)
        for scope in self._scopes:
            if scope.is_defined(name):
                return scope.lookup(name)
        assert isinstance(location, Location)
        raise ParseError(location, message=f"Undefined symbol: {name}")
