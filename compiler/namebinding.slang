
from utils import log_info, log_trace, panic
from location import Location
from datatypes import List, Option, Dictionary
import ast
from errors import CompilationError, new_error, new_errors


fn bind_names(module: ast.Module, module_map: Dictionary[ast.Module]) -> Option[CompilationError]:
    log_info("Filling scopes for {module.name}")
    let filler = ScopeFiller()
    let fil_vis = ast.Visitor:
        data: filler
        on_definition: filler_on_definition
        on_type: filler_on_type
        on_statement: filler_on_statement
        on_expression: filler_on_expression
        on_node: filler_on_node
    filler.enter_scope(module.scope)

    for imp in module.imports:
        import_mod(imp, module_map, filler)

    ast.visit_module(fil_vis, module)
    filler.leave_scope()
    if not filler.errors.is_empty():
        return Option.Some(new_errors(filler.errors))

    log_info("Binding names for {module.name}")
    let binder = NameBinder()
    let bind_visitor = ast.Visitor:
        data: binder
        on_definition: binder_on_definition
        on_type: binder_on_type
        on_statement: binder_on_statement
        on_expression: binder_on_expression
        on_node: binder_on_node
    binder.enter_scope(base_scope())
    binder.enter_scope(module.scope)
    ast.visit_module(bind_visitor, module)
    binder.leave_scope()
    binder.leave_scope()

    if not binder.errors.is_empty():
        return Option.Some(new_errors(binder.errors))

    return Option.None()

fn import_mod(imp: ast.Import, module_map: Dictionary[ast.Module], filler: ScopeFiller):
    log_trace("Import {imp.modname}")
    case module_map.get(imp.modname):
        Some(m):
            case imp.kind:
                Self:
                    filler.define(m.name, ast.Symbol.Mod(m))
                Names(names):
                    for name in names:
                        log_trace("Importing {name} from {imp.modname}")
                        case m.scope.lookup(name):
                            Some(sym):
                                filler.define(name, sym)
                            None:
                                filler.add_error(imp.location, "Error, module {m.name} has no symbol: {name}")
        None:
            filler.add_error(imp.location, "Error, no mod: {imp.modname}")

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
                Function(func):
                    filler.define(func.name, ast.Symbol.Function(func))
                    filler.enter_scope(func.scope)
                    for type_parameter in func.type_parameters:
                        filler.define(type_parameter.node_id.name, ast.Symbol.Type(ast.type_parameter_ref(type_parameter)))
                    for param_def in func.parameters:
                        filler.define(param_def.name, ast.Symbol.Parameter(param_def))
                ExternFunction(efunc):
                    pass
                Enum(e):
                    filler.define(e.name, ast.Symbol.TypeConstructor(ast.TyCon.Enum(e)))
                    filler.enter_scope(e.scope)
                    for type_parameter in e.type_parameters:
                        filler.define(type_parameter.node_id.name, ast.Symbol.Type(ast.type_parameter_ref(type_parameter)))
                    for variant in e.variants:
                        filler.define(variant.name, ast.Symbol.Variant(variant))
                Struct(s):
                    filler.define(s.node_id.name, ast.Symbol.TypeConstructor(ast.TyCon.Struct(s)))
                    filler.enter_scope(s.scope)
                    for type_parameter in s.type_parameters:
                        filler.define(type_parameter.node_id.name, ast.Symbol.Type(ast.type_parameter_ref(type_parameter)))
                    for field in s.fields:
                        filler.define(field.name, ast.Symbol.Field(field))
                Class(c):
                    filler.define(c.node_id.name, ast.Symbol.TypeConstructor(ast.TyCon.Class(c)))
                    filler.enter_scope(c.scope)
                    for type_parameter in c.type_parameters:
                        filler.define(type_parameter.node_id.name, ast.Symbol.Type(ast.type_parameter_ref(type_parameter)))
                    filler.define(c.this_var.name, ast.Symbol.Var(c.this_var))
                    for definition in c.definitions:
                        case definition:
                            Var(v):
                                pass
                            Function(func):
                                filler.define(func.name, ast.Symbol.Function(func))
                        else:
                            panic("class can only contain var/func")
                Var(v):
                    filler.define(v.variable.name, ast.Symbol.Var(v.variable))
        Post:
            case get_scope(definition):
                None:
                    pass
            else:
                filler.leave_scope()
    else:
        pass

fn filler_on_type(filler: ScopeFiller, ty: ast.MyType, phase: ast.VisitPhase):
    pass

fn filler_on_statement(filler: ScopeFiller, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Pre:
            case statement.kind:
                Let(letty):
                    filler.define(letty.variable.name, ast.Symbol.Var(letty.variable))
                For(for_statement):
                    filler.define(for_statement.iter_var.name, ast.Symbol.Var(for_statement.iter_var))
                Try(try_statement):
                    # TODO: create new scope for except clause?
                    filler.define(try_statement.except_param.name, ast.Symbol.Parameter(try_statement.except_param))
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
                    filler.enter_scope(arm.scope)
                    for v in arm.variables:
                        filler.define(v.name, ast.Symbol.Var(v))
        Post:
            case node:
                Arm(arm):
                    filler.leave_scope()
    else:
        pass


class ScopeFiller:
    var scopes: List[ast.Scope] = List()
    var errors: List[CompilationError] = List()

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
                Some(s):
                    binder.enter_scope(s)
        Post:
            case get_scope(definition):
                None:
                    pass
            else:
                binder.leave_scope()
    else:
        pass

fn binder_on_type(binder: NameBinder, ty: ast.MyType, phase: ast.VisitPhase):
    pass


fn binder_on_statement(binder: NameBinder, statement: ast.Statement, phase: ast.VisitPhase):
    pass

fn symbol_to_kind(symbol: ast.Symbol) -> ast.ExpressionKind:
    case symbol:
        Type(ty):
            return ast.ExpressionKind.Type(ty)
        TypeConstructor(tycon):
            return ast.ExpressionKind.TypeConstructor(tycon)
        Var(v):
            return ast.ExpressionKind.VarRef(v)
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
                            binder.add_error(expression.location, "'{name}' not defined!")
                GetAttr(base, attr):
                    case base.kind:
                        LoadSymbol(sym):
                            case sym:
                                Mod(m):
                                    case m.scope.lookup(attr):
                                        Some(symbol):
                                            expression.kind = symbol_to_kind(symbol)
                                        None:
                                            binder.add_error(expression.location, "module '{m.name}' has no symbol: '{attr}'")
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
                    binder.enter_scope(arm.scope)
        Post:
            case node:
                Arm(arm):
                    binder.leave_scope()
    else:
        pass

fn base_scope() -> ast.Scope:
    let s = ast.Scope()
    s.define("int", ast.Symbol.Type(ast.int_type()))
    s.define("str", ast.Symbol.Type(ast.str_type()))
    s.define("bool", ast.Symbol.Type(ast.bool_type()))
    s.define("float", ast.Symbol.Type(ast.float_type()))
    return s

class NameBinder:
    var scopes: List[ast.Scope] = List()
    var errors: List[CompilationError] = List()

    fn lookup(name: str) -> Option[ast.Symbol]:
        # print("Lookup: {name}")
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
