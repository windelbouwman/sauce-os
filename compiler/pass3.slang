
import ast
from std import print
from location import Location
from utils import log_info
from errors import new_error, new_errors, CompilationError
from datatypes import Dictionary, List, Option


fn resolve_newops(module: ast.Module) -> Option[CompilationError]:
    log_info("resolve new-ops for {module.name}")
    let newop = NewOp()
    let newop_visitor = ast.Visitor[NewOp]:
        data: newop
        on_definition: newop_on_definition
        on_type: newop_on_type
        on_statement: newop_on_statement
        on_expression: newop_on_expression
        on_node: newop_on_node
    ast.visit_module(newop_visitor, module)
    if newop.errors.is_empty():
        return Option.None()
    else:
        return Option.Some(new_errors(newop.errors))

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
                ast.change_type_to(ty, newop.eval_type_expr(expr))
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
                        newop.add_error(expression.location, "Error: duplicate field")
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
                    newop.add_error(expression.location, "Type {ast.type_to_string(ty)} is not struct")
            GetIndex(base, indici):
                case base.kind:
                    TypeConstructor(tycon):
                        let type_arguments: List[ast.MyType] = List()
                        for index in indici:
                            type_arguments.append(newop.eval_type_expr(index))
                        let ty = newop.tycon_apply2(tycon, type_arguments)
                        expression.kind = ast.ExpressionKind.Type(ty)
                else:
                    pass
        else:
            pass

fn newop_on_node(newop: NewOp, node: ast.VisitNode, is_pre: bool):
    pass

class NewOp:
    var errors: List[CompilationError] = List()

    fn eval_type_expr(expr: ast.Expression) -> ast.MyType:
        # Try to use this expression as a type.
        case expr.kind:
            Type(ty2):
                return ty2
            TypeConstructor(tycon):
                # TODO: check we do not require type arguments
                let type_arguments = List()
                let ty2 = this.tycon_apply2(tycon, type_arguments)
                return ty2
        else:
            let message = "Invalid type expr: {ast.expression_to_string(expr)}"
            this.add_error(expr.location, message)
            return ast.undefined_type()

    fn tycon_apply2(tycon: ast.TyCon, type_arguments: List[ast.MyType]) -> ast.MyType:
        # let type_arguments = List()
        return ast.new_type(ast.TypeKind.App(tycon, type_arguments))
    
    fn add_error(location: Location, message: str):
        this.errors.append(new_error(location, message))
