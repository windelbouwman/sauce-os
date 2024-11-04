
from utils import log_info, log_trace
from location import Location
from datatypes import List, Option, option_unwrap
from dicttype import Dictionary
import ast
from errors import CompilationError, new_error, new_errors, SingleCompilationError


fn bind_names(module: ast.Module, module_map: Dictionary[ast.Module], tycon_map: Dictionary[ast.TyCon]) except CompilationError:
    log_info("Filling scopes for {module.name}")
    let filler = ScopeFiller(tycon_map)
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
    let binder = NameBinder(tycon_map)
    let bind_visitor = new_bind_visitor(binder)
    binder.enter_scope(scope: base_scope())
    binder.enter_scope(scope: module.scope)
    ast.visit_module(visitor: bind_visitor, module)
    binder.leave_scope()
    binder.leave_scope()

    if not binder.errors.is_empty():
        raise new_errors(filename: module.filename, errors: binder.errors)

fn new_bind_visitor(binder: NameBinder) -> ast.Visitor[NameBinder]:
    ast.Visitor:
        data: binder
        on_definition: binder_on_definition
        on_type: binder_on_type
        on_statement: binder_on_statement
        on_expression: binder_on_expression
        on_node: binder_on_node

fn bind_names_expression(expression: ast.Expression) except CompilationError:
    let tycon_map: Dictionary[ast.TyCon] = Dictionary()
    let binder = NameBinder(tycon_map)
    let bind_visitor = new_bind_visitor(binder)
    ast.visit_expression(visitor: bind_visitor, expression)
    if not binder.errors.is_empty():
        raise new_errors(filename: Option.None(), errors: binder.errors)

fn import_mod(imp: ast.Import, module_map: Dictionary[ast.Module], filler: ScopeFiller):
    log_trace("Import {imp.modname}")
    case module_map.maybe_get(key: imp.modname):
        Some(m):
            case imp.kind:
                Self:
                    filler.define(name: m.name, symbol: ast.Symbol.Mod(m), location: imp.location)
                Names(names):
                    for name in names:
                        log_trace("Importing {name} from {imp.modname}")
                        case m.scope.lookup(name):
                            Some(symbol):
                                filler.define(name, symbol, location: imp.location)
                            None:
                                filler.add_error(location: imp.location, message: "Error, module {m.name} has no symbol: {name}")
        None:
            filler.add_error(location: imp.location, message: "Error, no module named: {imp.modname}")

fn get_scope(definition: ast.Definition) -> Option[ast.Scope]:
    # try to retrieve a scope, if we have one
    case definition:
        Macro(macro_def):
            Option.None()
        Function(function_def):
            case function_def.body:
                Intern(scoped_block):
                    Option.Some(scoped_block.scope)
                Extern(libname):
                    Option[ast.Scope].None()
        Enum(enum_def):
            Option.Some(enum_def.scope)
        Struct(struct_def):
            Option.Some(struct_def.scope)
        Class(class_def):
            Option.Some(class_def.scope)
        Var(v):
            Option[ast.Scope].None()

fn filler_on_definition(filler: ScopeFiller, definition: ast.Definition, phase: ast.VisitPhase):
    case phase:
        Pre:
            case definition:
                Macro(macro_def):
                    filler.define(name: macro_def.name, symbol: ast.Symbol.Macro(macro_def), location: macro_def.location)
                Function(function_def):
                    filler.define(name: function_def.name, symbol: ast.Symbol.Function(function_def), location: function_def.location)
                    case function_def.body:
                        Intern(scoped_block):
                            filler.enter_scope(scope: scoped_block.scope)
                            for type_parameter in function_def.type_parameters:
                                filler.define_type_parameter(type_parameter)
                            for parameter_def in function_def.parameters:
                                filler.define_parameter(parameter_def)
                            case function_def.this_parameter:
                                Some(this_parameter2):
                                    filler.define_parameter(parameter_def: this_parameter2)
                                None:
                                    pass
                        Extern(libname):
                            pass
                Enum(enum_def):
                    filler.add_tycon(id: enum_def.id, tycon: ast.TyCon.Enum(enum_def))
                    filler.define(name: enum_def.id.name, symbol: ast.Symbol.TypeConstructor(tycon: ast.TyCon.Enum(enum_def)), location: enum_def.location)
                    filler.enter_scope(scope: enum_def.scope)
                    for type_parameter in enum_def.type_parameters:
                        filler.define_type_parameter(type_parameter)
                    for variant in enum_def.variants:
                        filler.define(name: variant.name, symbol: ast.Symbol.Variant(variant), location: variant.location)
                Struct(struct_def):
                    filler.add_tycon(id: struct_def.id, tycon: ast.TyCon.Struct(struct_def))
                    filler.define(name: struct_def.id.name, symbol: ast.Symbol.TypeConstructor(tycon: ast.TyCon.Struct(struct_def)), location: struct_def.location)
                    filler.enter_scope(scope: struct_def.scope)
                    for type_parameter in struct_def.type_parameters:
                        filler.define_type_parameter(type_parameter)
                    for field in struct_def.fields:
                        filler.define(name: field.name, symbol: ast.Symbol.Field(field), location: field.location)
                Class(class_def):
                    filler.add_tycon(id: class_def.id, tycon: ast.TyCon.Class(class_def))
                    filler.define(name: class_def.id.name, symbol: ast.Symbol.TypeConstructor(tycon: ast.TyCon.Class(class_def)), location: class_def.location)
                    filler.enter_scope(scope: class_def.scope)
                    for type_parameter in class_def.type_parameters:
                        filler.define_type_parameter(type_parameter)
                Var(variable_def):
                    filler.define_variable(variable: variable_def.variable)
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
                    filler.define_variable(variable: letty.variable)
                For(for_statement):
                    filler.enter_scope(scope: for_statement.block.scope)
                    filler.define_variable(variable: for_statement.iter_var)
                While(while_statement):
                    filler.enter_scope(scope: while_statement.block.scope)
                Loop(loop_statement):
                    filler.enter_scope(scope: loop_statement.block.scope)
                Try(try_statement):
                    # TODO: create new scope for except clause?
                    filler.define_variable(variable: try_statement.except_var)
            else:
                pass
        Post:
            case statement.kind:
                For(for_statement):
                    filler.leave_scope()
                While(while_statement):
                    filler.leave_scope()
                Loop(loop_statement):
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
                        filler.define_variable(variable)
                ScopeNode(scope):
                    filler.enter_scope(scope)
            else:
                pass
        Post:
            case node:
                Arm(arm):
                    filler.leave_scope()
                ScopeNode(scope):
                    filler.leave_scope()
            else:
                pass
    else:
        pass


class ScopeFiller:
    var scopes: List[ast.Scope] = List()
    var errors: List[SingleCompilationError] = List()
    var tycon_map: Dictionary[ast.TyCon]

    fn add_tycon(id: ast.NodeId, tycon: ast.TyCon):
        tycon_map.insert(key: ast.node_id_to_string(id), value: tycon)

    fn define_variable(variable: ast.Variable):
        define(name: variable.id.name, symbol: ast.Symbol.Var(variable), location: variable.location)
    
    fn define_type_parameter(type_parameter: ast.TypeParameter):
        define(name: type_parameter.id.name, symbol: ast.Symbol.Typ(ty: ast.type_parameter_ref(type_parameter)), location: type_parameter.location)
    
    fn define_parameter(parameter_def: ast.ParameterDef):
        define(name: parameter_def.id.name, symbol: ast.Symbol.Parameter(parameter_def), location: parameter_def.location)

    fn define(name: str, symbol: ast.Symbol, location: Location):
        # log_trace("DEFINE {name}")
        let scope = scopes.last()
        if scope.is_defined(name):
            add_error(location, message: "Symbol '{name}' is already defined")
        else:
            scope.define(name, symbol)
    
    fn enter_scope(scope: ast.Scope):
        scopes.append(scope)
    
    fn leave_scope():
        let unused = scopes.pop_last()

    fn add_error(location: Location, message: str):
        let err = new_error(location, message)
        errors.append(err)

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
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Ref(key):
                    let tycon = binder.tycon_map.get(key)
                    ty.kind = ast.TypeKind.App(tycon, type_arguments)
            else:
                pass
    else:
        pass


fn binder_on_statement(binder: NameBinder, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Pre:
            case statement.kind:
                For(for_statement):
                    binder.enter_scope(scope: for_statement.block.scope)
                While(while_statement):
                    binder.enter_scope(scope: while_statement.block.scope)
                Loop(loop_statement):
                    binder.enter_scope(scope: loop_statement.block.scope)
            else:
                pass
        Post:
            case statement.kind:
                For(for_statement):
                    binder.leave_scope()
                While(while_statement):
                    binder.leave_scope()
                Loop(loop_statement):
                    binder.leave_scope()
            else:
                pass
    else:
        pass

fn symbol_to_kind(symbol: ast.Symbol) -> ast.ExpressionKind:
    case symbol:
        Typ(ty):
            ast.ExpressionKind.Typ(ty)
        TypeConstructor(tycon):
            ast.ExpressionKind.TypeConstructor(tycon)
        Var(variable):
            ast.ExpressionKind.VarRef(variable)
        Parameter(parameter_def):
            ast.ExpressionKind.ParameterRef(parameter_def)
    else:
        ast.ExpressionKind.LoadSymbol(symbol)

fn binder_on_expression(binder: NameBinder, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                NameRef(name):
                    case binder.lookup2(name, location: expression.location):
                        Some(kind):
                            expression.kind = kind
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
            else:
                pass
        Post:
            case node:
                Arm(arm):
                    binder.leave_scope()
                ScopeNode(scope):
                    binder.leave_scope()
            else:
                pass
    else:
        pass

fn base_scope() -> ast.Scope:
    let s = ast.Scope()
    s.define(name: "int", symbol: ast.Symbol.Typ(ty: ast.int_type()))
    s.define(name: "uint8", symbol: ast.Symbol.Typ(ty: ast.uint8_type()))
    s.define(name: "uint16", symbol: ast.Symbol.Typ(ty: ast.uint16_type()))
    s.define(name: "uint32", symbol: ast.Symbol.Typ(ty: ast.uint32_type()))
    s.define(name: "uint64", symbol: ast.Symbol.Typ(ty: ast.uint64_type()))
    s.define(name: "int8", symbol: ast.Symbol.Typ(ty: ast.int8_type()))
    s.define(name: "int16", symbol: ast.Symbol.Typ(ty: ast.int16_type()))
    s.define(name: "int32", symbol: ast.Symbol.Typ(ty: ast.int32_type()))
    s.define(name: "int64", symbol: ast.Symbol.Typ(ty: ast.int64_type()))
    s.define(name: "str", symbol: ast.Symbol.Typ(ty: ast.str_type()))
    s.define(name: "char", symbol: ast.Symbol.Typ(ty: ast.char_type()))
    s.define(name: "bool", symbol: ast.Symbol.Typ(ty: ast.bool_type()))
    s.define(name: "float", symbol: ast.Symbol.Typ(ty: ast.float_type()))
    s.define(name: "float32", symbol: ast.Symbol.Typ(ty: ast.float32_type()))
    s.define(name: "float64", symbol: ast.Symbol.Typ(ty: ast.float64_type()))
    s

class NameBinder:
    var scopes: List[ast.Scope] = List()
    var errors: List[SingleCompilationError] = List()
    var tycon_map: Dictionary[ast.TyCon]

    fn lookup2(name: str, location: Location) -> Option[ast.ExpressionKind]:
        for scope in scopes:
            case scope.lookup(name):
                Some(symbol):
                    let introduce_this = false
                    if scope.class_scope:
                        case symbol:
                            Function(function_def):
                                introduce_this = true
                            Var(var_def):
                                introduce_this = true
                        else:
                            pass

                    if introduce_this:
                        let base = option_unwrap(lookup3(name: "this", location))
                        let kind = ast.ExpressionKind.GetAttr(base, field: name)
                        return Option.Some(kind)
                    else:
                        let kind = symbol_to_kind(symbol)
                        return Option.Some(kind)
                None:
                    pass
        Option.None()

    fn lookup3(name: str, location: Location) -> Option[ast.Expression]:
        for scope in scopes:
            case scope.lookup(name):
                Some(symbol):
                    let kind = symbol_to_kind(symbol)
                    let expr = ast.Expression(kind, ty: ast.undefined_type(), location)
                    return Option.Some(expr)
                None:
                    pass
        Option.None()

    fn enter_scope(scope: ast.Scope):
        scopes.prepend(scope)
    
    fn leave_scope():
        let unused = scopes.pop_front()
    
    fn add_error(location: Location, message: str):
        let err = new_error(location, message)
        errors.append(err)
