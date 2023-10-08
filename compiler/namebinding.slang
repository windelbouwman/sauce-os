
from utils import log_info, log_trace, panic
from location import Location
from datatypes import List, Option, Dictionary
import ast
from errors import CompilationError, new_error, new_errors, SingleCompilationError


fn bind_names(module: ast.Module, module_map: Dictionary[ast.Module]) except CompilationError:
    log_info("Filling scopes for {module.name}")
    let filler = ScopeFiller()
    let fil_vis = ast.Visitor:
        data: filler
        on_definition: filler_on_definition
        on_type: filler_on_type
        on_statement: filler_on_statement
        on_expression: filler_on_expression
        on_node: filler_on_node
    filler.enter_scope(scope: module.scope)

    for imp in module.imports:
        import_mod(imp, module_map, filler)

    ast.visit_module(visitor: fil_vis, module)
    filler.leave_scope()
    if not filler.errors.is_empty():
        raise new_errors(filename: module.filename, errors: filler.errors)

    log_info("Binding names for {module.name}")
    let binder = NameBinder()
    let bind_visitor = ast.Visitor:
        data: binder
        on_definition: binder_on_definition
        on_type: binder_on_type
        on_statement: binder_on_statement
        on_expression: binder_on_expression
        on_node: binder_on_node
    binder.enter_scope(scope: base_scope())
    binder.enter_scope(scope: module.scope)
    ast.visit_module(visitor: bind_visitor, module)
    binder.leave_scope()
    binder.leave_scope()

    if not binder.errors.is_empty():
        raise new_errors(filename: module.filename, errors: binder.errors)

    return

fn import_mod(imp: ast.Import, module_map: Dictionary[ast.Module], filler: ScopeFiller):
    log_trace("Import {imp.modname}")
    case module_map.get(key: imp.modname):
        Some(m):
            case imp.kind:
                Self:
                    filler.define(name: m.name, symbol: ast.Symbol.Mod(m))
                Names(names):
                    for name in names:
                        log_trace("Importing {name} from {imp.modname}")
                        case m.scope.lookup(name):
                            Some(symbol):
                                filler.define(name, symbol)
                            None:
                                filler.add_error(location: imp.location, message: "Error, module {m.name} has no symbol: {name}")
        None:
            filler.add_error(location: imp.location, message: "Error, no mod: {imp.modname}")

fn get_scope(definition: ast.Definition) -> Option[ast.Scope]:
    # try to retrieve a scope, if we have one
    case definition:
        Function(func):
            return Option.Some(func.scope)
        ExternFunction(efunc):
            return Option.None()
        Enum(e):
            return Option.Some(e.scope)
        Struct(s):
            return Option.Some(s.scope)
        Class(c):
            return Option.Some(c.scope)
        Var(v):
            return Option.None()

fn filler_on_definition(filler: ScopeFiller, definition: ast.Definition, phase: ast.VisitPhase):
    case phase:
        Pre:
            case definition:
                Function(function_def):
                    filler.define(name: function_def.id.name, symbol: ast.Symbol.Function(function_def))
                    filler.enter_scope(scope: function_def.scope)
                    for type_parameter in function_def.type_parameters:
                        filler.define(name: type_parameter.id.name, symbol: ast.Symbol.Typ(ty: ast.type_parameter_ref(type_parameter)))
                    for parameter_def in function_def.parameters:
                        filler.define(name: parameter_def.id.name, symbol: ast.Symbol.Parameter(parameter_def))
                    case function_def.this_parameter:
                        Some(this_parameter2):
                            filler.define(name: this_parameter2.id.name, symbol: ast.Symbol.Parameter(this_parameter2))
                        None:
                            pass
                ExternFunction(efunc):
                    pass
                Enum(enum_def):
                    filler.define(name: enum_def.id.name, symbol: ast.Symbol.TypeConstructor(tycon: ast.TyCon.Enum(enum_def)))
                    filler.enter_scope(scope: enum_def.scope)
                    for type_parameter in enum_def.type_parameters:
                        filler.define(name: type_parameter.id.name, symbol: ast.Symbol.Typ(ty: ast.type_parameter_ref(type_parameter)))
                    for variant in enum_def.variants:
                        filler.define(name: variant.name, symbol: ast.Symbol.Variant(variant))
                Struct(struct_def):
                    filler.define(name: struct_def.id.name, symbol: ast.Symbol.TypeConstructor(tycon: ast.TyCon.Struct(struct_def)))
                    filler.enter_scope(scope: struct_def.scope)
                    for type_parameter in struct_def.type_parameters:
                        filler.define(name: type_parameter.id.name, symbol: ast.Symbol.Typ(ty: ast.type_parameter_ref(type_parameter)))
                    for field in struct_def.fields:
                        filler.define(name: field.name, symbol: ast.Symbol.Field(field))
                Class(class_def):
                    filler.define(name: class_def.id.name, symbol: ast.Symbol.TypeConstructor(tycon: ast.TyCon.Class(class_def)))
                    filler.enter_scope(scope: class_def.scope)
                    for type_parameter in class_def.type_parameters:
                        filler.define(name: type_parameter.id.name, symbol: ast.Symbol.Typ(ty: ast.type_parameter_ref(type_parameter)))
                    for definition in class_def.definitions:
                        case definition:
                            Var(v):
                                pass
                            Function(function_def):
                                filler.define(name: function_def.id.name, symbol: ast.Symbol.Function(function_def))
                        else:
                            panic("class can only contain var/func")
                Var(variable_def):
                    filler.define(name: variable_def.variable.id.name, symbol: ast.Symbol.Var(variable: variable_def.variable))
        Post:
            case get_scope(definition):
                None:
                    pass
            else:
                filler.leave_scope()
    else:
        pass

fn filler_on_type(filler: ScopeFiller, ty: ast.Type, phase: ast.VisitPhase):
    pass

fn filler_on_statement(filler: ScopeFiller, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Pre:
            case statement.kind:
                Let(letty):
                    filler.define(name: letty.variable.id.name, symbol: ast.Symbol.Var(variable: letty.variable))
                For(for_statement):
                    filler.enter_scope(scope: for_statement.block.scope)
                    filler.define(name: for_statement.iter_var.id.name, symbol: ast.Symbol.Var(variable: for_statement.iter_var))
                Try(try_statement):
                    # TODO: create new scope for except clause?
                    filler.define(name: try_statement.except_param.id.name, symbol: ast.Symbol.Parameter(parameter: try_statement.except_param))
            else:
                pass
        Post:
            case statement.kind:
                For(for_statement):
                    filler.leave_scope()
            else:
                pass
    else:
        pass

fn filler_on_expression(filler: ScopeFiller, expression: ast.Expression, phase: ast.VisitPhase):
    pass

fn filler_on_node(filler: ScopeFiller, node: ast.VisitNode, phase: ast.VisitPhase):
    case phase:
        Pre:
            case node:
                Arm(arm):
                    filler.enter_scope(scope: arm.block.scope)
                    for variable in arm.variables:
                        filler.define(name: variable.id.name, symbol: ast.Symbol.Var(variable))
                ScopeNode(scope):
                    filler.enter_scope(scope)
        Post:
            case node:
                Arm(arm):
                    filler.leave_scope()
                ScopeNode(scope):
                    filler.leave_scope()
    else:
        pass


class ScopeFiller:
    var scopes: List[ast.Scope] = List()
    var errors: List[SingleCompilationError] = List()

    fn define(name: str, symbol: ast.Symbol):
        # log_trace("DEFINE {name}")
        this.scopes.last().define(name, symbol)
    
    fn enter_scope(scope: ast.Scope):
        this.scopes.append(scope)
    
    fn leave_scope():
        let unused = this.scopes.pop_last()

    fn add_error(location: Location, message: str):
        let err = new_error(location, message)
        this.errors.append(err)

fn binder_on_definition(binder: NameBinder, definition: ast.Definition, phase: ast.VisitPhase):
    case phase:
        Pre:
            case get_scope(definition):
                None:
                    pass
                Some(scope):
                    binder.enter_scope(scope)
        Post:
            case get_scope(definition):
                None:
                    pass
            else:
                binder.leave_scope()
    else:
        pass

fn binder_on_type(binder: NameBinder, ty: ast.Type, phase: ast.VisitPhase):
    pass


fn binder_on_statement(binder: NameBinder, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Pre:
            case statement.kind:
                For(for_statement):
                    binder.enter_scope(scope: for_statement.block.scope)
            else:
                pass
        Post:
            case statement.kind:
                For(for_statement):
                    binder.leave_scope()
            else:
                pass
    else:
        pass

fn symbol_to_kind(symbol: ast.Symbol) -> ast.ExpressionKind:
    case symbol:
        Typ(ty):
            return ast.ExpressionKind.Typ(ty)
        TypeConstructor(tycon):
            return ast.ExpressionKind.TypeConstructor(tycon)
        Var(variable):
            return ast.ExpressionKind.VarRef(variable)
    else:
        return ast.ExpressionKind.LoadSymbol(symbol)

fn binder_on_expression(binder: NameBinder, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                NameRef(name):
                    case binder.lookup(name):
                        Some(symbol):
                            expression.kind = symbol_to_kind(symbol)
                        None:
                            binder.add_error(location: expression.location, message: "'{name}' not defined!")
                GetAttr(base, attr):
                    case base.kind:
                        LoadSymbol(sym):
                            case sym:
                                Mod(m):
                                    case m.scope.lookup(name: attr):
                                        Some(symbol):
                                            expression.kind = symbol_to_kind(symbol)
                                        None:
                                            binder.add_error(location: expression.location, message: "module '{m.name}' has no symbol: '{attr}'")
                            else:
                                pass
                    else:
                        pass
            else:
                pass
    else:
        pass

fn binder_on_node(binder: NameBinder, node: ast.VisitNode, phase: ast.VisitPhase):
    case phase:
        Pre:
            case node:
                Arm(arm):
                    binder.enter_scope(scope: arm.block.scope)
                ScopeNode(scope):
                    binder.enter_scope(scope)
        Post:
            case node:
                Arm(arm):
                    binder.leave_scope()
                ScopeNode(scope):
                    binder.leave_scope()
    else:
        pass

fn base_scope() -> ast.Scope:
    let s = ast.Scope()
    s.define(name: "int", symbol: ast.Symbol.Typ(ty: ast.int_type()))
    s.define(name: "str", symbol: ast.Symbol.Typ(ty: ast.str_type()))
    s.define(name: "char", symbol: ast.Symbol.Typ(ty: ast.char_type()))
    s.define(name: "bool", symbol: ast.Symbol.Typ(ty: ast.bool_type()))
    s.define(name: "float", symbol: ast.Symbol.Typ(ty: ast.float_type()))
    return s

class NameBinder:
    var scopes: List[ast.Scope] = List()
    var errors: List[SingleCompilationError] = List()

    fn lookup(name: str) -> Option[ast.Symbol]:
        for scope in this.scopes:
            case scope.lookup(name):
                Some(s):
                    return Option.Some(s)
                None:
                    pass
        return Option.None()

    fn enter_scope(scope: ast.Scope):
        this.scopes.prepend(scope)
    
    fn leave_scope():
        let unused = this.scopes.pop_front()
    
    fn add_error(location: Location, message: str):
        let err = new_error(location, message)
        this.errors.append(err)
