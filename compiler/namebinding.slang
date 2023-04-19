
from std import print
from datatypes import List, Option
import ast

fn get_std_module() -> ast.Module:
    let m = ast.new_module("str", List(), List())
    return m

fn bind_names(module: ast.Module):
    print("Filling scopes")
    let filler = ScopeFiller()
    let fil_vis = ast.Visitor:
        data: filler
        on_definition: filler_on_definition
        on_statement: filler_on_statement
        on_expression: filler_on_expression
    filler.enter_scope(module.scope)
    ast.visit_module(fil_vis, module)
    filler.leave_scope()

    print("Binding names")
    let binder = NameBinder()
    let bind_visitor = ast.Visitor:
        data: binder
        on_definition: binder_on_definition
        on_statement: binder_on_statement
        on_expression: binder_on_expression
    let std_module = get_std_module()
    module.scope.define("std", ast.Symbol.Mod(std_module))
    binder.enter_scope(module.scope)
    ast.visit_module(bind_visitor, module)
    binder.leave_scope()

fn filler_on_definition(filler: ScopeFiller, definition: ast.Definition, is_pre: bool):
    if is_pre:
        case definition:
            Function(func):
                filler.define(func.name, ast.Symbol.Function(func))
                filler.enter_scope(func.scope)
                for param_def in func.parameters:
                    filler.define(param_def.name, ast.Symbol.Parameter(param_def))
            Enum(e):
                filler.define(e.name, ast.Symbol.Enum(e))
                filler.enter_scope(e.scope)
            Struct(s):
                filler.define(s.name, ast.Symbol.Struct(s))
                filler.enter_scope(s.scope)
            Class(c):
                filler.define(c.name, ast.Symbol.Class(c))
                filler.enter_scope(c.scope)
            Var(v):
                filler.define(v.variable.name, ast.Symbol.Var(v.variable))
    else:
        case definition:
            Var(v):
                pass
        else:
            filler.leave_scope()

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
        else:
            binder.leave_scope()


fn binder_on_statement(binder: NameBinder, expression: ast.Statement, is_pre: bool):
    pass

fn binder_on_expression(binder: NameBinder, expression: ast.Expression, is_pre: bool):
    if is_pre:
        case expression.kind:
            NameRef(name):
                case binder.lookup(name):
                    Some(symbol):
                        expression.kind = ast.ExpressionKind.LoadSymbol(symbol)
                    None:
                        print("ERROR: {name} not defined!")
        else:
            pass

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
