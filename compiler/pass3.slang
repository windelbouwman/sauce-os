
import ast
from std import print
from datatypes import Dictionary, List


fn resolve_newops(module: ast.Module):
    print("resolve new-ops for {module.name}")
    let newop = NewOp()
    let newop_visitor = ast.Visitor[NewOp]:
        data: newop
        on_definition: newop_on_definition
        on_type: newop_on_type
        on_statement: newop_on_statement
        on_expression: newop_on_expression
    ast.visit_module(newop_visitor, module)

fn tycon_apply2(tycon: ast.TyCon) -> ast.MyType:
    let type_arguments = List()
    return ast.new_type(ast.TypeKind.App(tycon, type_arguments))

fn newop_on_definition(newop: NewOp, definition: ast.Definition, is_pre: bool):
    if is_pre:
        pass
    else:
        pass

fn newop_on_type(newop: NewOp, ty: ast.MyType, is_pre: bool):
    if is_pre:
        pass
    else:
        case ty.kind:
            TypeExpression(expr):
                case expr.kind:
                    Type(ty2):
                        ty.kind = ty2.kind
                    TypeConstructor(tycon):
                        let ty2 = tycon_apply2(tycon)
                        ty.kind = ty2.kind
                else:
                    print("Invalid type expr: {ast.expression_to_string(expr)}")
        else:
            pass


fn newop_on_statement(newop: NewOp, statement: ast.Statement, is_pre: bool):
    pass

fn newop_on_expression(newop: NewOp, expression: ast.Expression, is_pre: bool):
    if is_pre:
        pass
    else:
        case expression.kind:
            ObjInit(ty, labeled_fields):
                let value_map: Dictionary[ast.Expression] = Dictionary()
                for labeled_field in labeled_fields:
                    if value_map.contains(labeled_field.name):
                        print("Error: duplicate field")
                    else:
                        value_map.insert(labeled_field.name, labeled_field.value)
                
                # Check that type is struct?
                let ok = false
                case ty.kind:
                    App(tycon, type_arguments):
                        case tycon:
                            Struct(struct_def):
                                ok = true
                                let values: List[ast.Expression] = List()
                                expression.kind = ast.ExpressionKind.StructLiteral(ty, values)
                        else:
                            pass
                else:
                    pass

                if not ok:
                    print("Type {ast.type_to_string(ty)} is not struct")
        else:
            pass


class NewOp:
    var a: int = 2

