
from std import print
from datatypes import List
import ast

fn bind_names(module: ast.Module):
    print("Filling scopes")
    let filler = ScopeFiller()
    let fil_vis = ast.Visitor:
        data: filler
        on_definition: filler_on_definition
        on_statement: filler_on_statement
        on_expression: filler_on_expression
    ast.visit_module(fil_vis, module)

    print("Binding names")
    let binder = NameBinder()
    let bind_visitor = ast.Visitor:
        data: binder
        on_definition: binder_on_definition
        on_statement: binder_on_statement
        on_expression: binder_on_expression
    ast.visit_module(bind_visitor, module)

fn filler_on_definition(filler: ScopeFiller, definition: ast.Definition, is_pre: bool):
    if is_pre:
        case definition:
            Function(func):
                filler.define(func.name)
        filler.enter_scope()
    else:
        filler.leave_scope()

fn filler_on_statement(filler: ScopeFiller, expression: ast.Statement, is_pre: bool):
    pass

fn filler_on_expression(filler: ScopeFiller, expression: ast.Expression, is_pre: bool):
    pass

class Scope:
    var x: int = 0

class ScopeFiller:
    var scopes: List[Scope] = List()

    fn define(name: str):
        print("DEFINE {name}")
    
    fn enter_scope():
        let scope = Scope()
        this.scopes.append(scope)
    
    fn leave_scope():
        let unused = this.scopes.pop_last()

fn binder_on_definition(filler: NameBinder, definition: ast.Definition, is_pre: bool):
    pass

fn binder_on_statement(binder: NameBinder, expression: ast.Statement, is_pre: bool):
    pass

fn binder_on_expression(binder: NameBinder, expression: ast.Expression, is_pre: bool):
    if is_pre:
        case expression.kind:
            NameRef(name):
                # print("Ref name: {name}")
                binder.lookup(name)
        else:
            pass

class NameBinder:
    var scope: int = 0

    fn lookup(name: str):
        print("Lookup: {name}")
