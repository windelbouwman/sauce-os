
from std import print
from datatypes import List, Option, Dictionary
import ast
from errors import CompilationError, new_error, display_error


fn bind_names(module: ast.Module, module_map: Dictionary[ast.Module]):
    print("Filling scopes for {module.name}")
    let filler = ScopeFiller()
    let fil_vis = ast.Visitor:
        data: filler
        on_definition: filler_on_definition
        on_type: filler_on_type
        on_statement: filler_on_statement
        on_expression: filler_on_expression
    filler.enter_scope(module.scope)

    for imp in module.imports:
        case module_map.get(imp.modname):
            Some(m):
                case imp.kind:
                    Self:
                        filler.define(m.name, ast.Symbol.Mod(m))
                    Names(names):
                        for name in names:
                            case m.scope.lookup(name):
                                Some(sym):
                                    filler.define(name, sym)
                                None:
                                    print("Error, module {m.name} has no symbol: {name}")
            None:
                print("Error, no mod: {imp.modname}")

    ast.visit_module(fil_vis, module)
    filler.leave_scope()

    print("Binding names for {module.name}")
    let binder = NameBinder()
    let bind_visitor = ast.Visitor:
        data: binder
        on_definition: binder_on_definition
        on_type: binder_on_type
        on_statement: binder_on_statement
        on_expression: binder_on_expression
    binder.enter_scope(base_scope())
    binder.enter_scope(module.scope)
    ast.visit_module(bind_visitor, module)
    binder.leave_scope()
    binder.leave_scope()

fn filler_on_definition(filler: ScopeFiller, definition: ast.Definition, is_pre: bool):
    if is_pre:
        case definition:
            Function(func):
                filler.define(func.name, ast.Symbol.Function(func))
                filler.enter_scope(func.scope)
                for param_def in func.parameters:
                    filler.define(param_def.name, ast.Symbol.Parameter(param_def))
            ExternFunction(efunc):
                pass
            Enum(e):
                filler.define(e.name, ast.Symbol.TypeConstructor(ast.TyCon.Enum(e)))
                filler.enter_scope(e.scope)
            Struct(s):
                filler.define(s.name, ast.Symbol.TypeConstructor(ast.TyCon.Struct(s)))
                filler.enter_scope(s.scope)
            Class(c):
                filler.define(c.name, ast.Symbol.TypeConstructor(ast.TyCon.Class(c)))
                filler.enter_scope(c.scope)
            Var(v):
                filler.define(v.variable.name, ast.Symbol.Var(v.variable))
    else:
        case definition:
            Var(v):
                pass
            ExternFunction(efunc):
                pass
        else:
            filler.leave_scope()

fn filler_on_type(filler: ScopeFiller, ty: ast.MyType, is_pre: bool):
    pass

fn filler_on_statement(filler: ScopeFiller, statement: ast.Statement, is_pre: bool):
    if is_pre:
        case statement.kind:
            Let(letty):
                filler.define(letty.variable.name, ast.Symbol.Var(letty.variable))
        else:
            pass
    else:
        pass

fn filler_on_expression(filler: ScopeFiller, expression: ast.Expression, is_pre: bool):
    pass

class ScopeFiller:
    var scopes: List[ast.Scope] = List()

    fn define(name: str, symbol: ast.Symbol):
        # print("DEFINE {name}")
        this.scopes.last().define(name, symbol)
    
    fn enter_scope(scope: ast.Scope):
        this.scopes.append(scope)
    
    fn leave_scope():
        let unused = this.scopes.pop_last()

fn binder_on_definition(binder: NameBinder, definition: ast.Definition, is_pre: bool):
    if is_pre:
        case definition:
            Function(func):
                binder.enter_scope(func.scope)
            ExternFunction(efunc):
                pass
            Enum(e):
                binder.enter_scope(e.scope)
            Struct(s):
                binder.enter_scope(s.scope)
            Class(c):
                binder.enter_scope(c.scope)
            Var(v):
                pass
    else:
        case definition:
            Var(v):
                pass
            ExternFunction(efunc):
                pass
        else:
            binder.leave_scope()

fn binder_on_type(binder: NameBinder, ty: ast.MyType, is_pre: bool):
    pass


fn binder_on_statement(binder: NameBinder, statement: ast.Statement, is_pre: bool):
    pass

fn binder_on_expression(binder: NameBinder, expression: ast.Expression, is_pre: bool):
    if is_pre:
        case expression.kind:
            NameRef(name):
                case binder.lookup(name):
                    Some(symbol):
                        case symbol:
                            Type(ty):
                                expression.kind = ast.ExpressionKind.Type(ty)
                            TypeConstructor(tycon):
                                expression.kind = ast.ExpressionKind.TypeConstructor(tycon)
                            Var(v):
                                expression.kind = ast.ExpressionKind.VarRef(v)
                        else:
                            expression.kind = ast.ExpressionKind.LoadSymbol(symbol)
                    None:
                        let err = new_error(expression.location, "'{name}' not defined!")
                        display_error(err)
        else:
            pass

fn base_scope() -> ast.Scope:
    let s = ast.Scope()
    s.define("int", ast.Symbol.Type(ast.int_type()))
    s.define("str", ast.Symbol.Type(ast.str_type()))
    return s

class NameBinder:
    var scopes: List[ast.Scope] = List()

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
