
import ast
from std import print
from location import Location
from utils import log_info, panic
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

fn newop_on_definition(newop: NewOp, definition: ast.Definition, phase: ast.VisitPhase):
    pass

fn newop_on_type(newop: NewOp, ty: ast.MyType, phase: ast.VisitPhase):
    case phase:
        Post:
            case ty.kind:
                TypeExpression(expr):
                    ast.change_type_to(ty, newop.eval_type_expr(expr))
            else:
                pass
    else:
        pass


fn newop_on_statement(newop: NewOp, statement: ast.Statement, phase: ast.VisitPhase):
    pass

fn newop_on_expression(newop: NewOp, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
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
                                    for field in struct_def.fields:
                                        case value_map.pop(field.name):
                                            Some(v):
                                                values.append(v)
                                            None:
                                                newop.add_error(expression.location, "Missing field: {field.name}")
                                    
                                    for name in value_map:
                                        newop.add_error(expression.location, "Superfluous field: {name}")

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
                            let ty = ast.apply_tycon(tycon, type_arguments)
                            expression.kind = ast.ExpressionKind.Type(ty)
                    else:
                        pass

                GetAttr(base, attr):
                    case newop.try_as_type(base):
                        None:
                            pass
                        Some(ty3):
                            if ast.is_enum_type(ty3):
                                case ast.get_enum_variant(ty3, attr):
                                    Some(variant):
                                        expression.kind = ast.ExpressionKind.Variant(ty3, variant)
                                    None:
                                        newop.add_error(expression.location, "No such enum variant: {attr}")
                                    
                            else:
                                newop.add_error(expression.location, "Can only get attr from enum type, not {ast.type_to_string(ty3)}")
                    
                Call(call):
                    case call.callee.kind:
                        TypeConstructor(tycon):
                            let ty2 = newop.turn_tycon_to_type(tycon)
                            expression.kind = ast.ExpressionKind.ClassLiteral(ty2)
                        Variant(ty, variant):
                            expression.kind = ast.ExpressionKind.EnumLiteral(ty, variant, call.arguments)
                    else:
                        pass
            else:
                pass
    else:
        pass

fn newop_on_node(newop: NewOp, node: ast.VisitNode, phase: ast.VisitPhase):
    pass

class NewOp:
    var errors: List[CompilationError] = List()
    var counter: int = 1

    fn try_as_type(expr: ast.Expression) -> Option[ast.MyType]:
        # Try to use this expression as a type.
        case expr.kind:
            Type(ty2):
                return Option.Some(ty2)
            TypeConstructor(tycon):
                let ty2 = this.turn_tycon_to_type(tycon)
                return Option.Some(ty2)
        else:
            return Option.None()

    fn eval_type_expr(expr: ast.Expression) -> ast.MyType:
        # Try to use this expression as a type.
        case this.try_as_type(expr):
            Some(ty2):
                return ty2
            None:
                let message = "Invalid type expr: {ast.expression_to_string(expr)}"
                this.add_error(expr.location, message)
                return ast.undefined_type()

    fn add_error(location: Location, message: str):
        this.errors.append(new_error(location, message))
    
    fn turn_tycon_to_type(tycon: ast.TyCon) -> ast.MyType:
        let type_arguments: List[ast.MyType] = List()
        for tp in ast.tycon_get_type_parameters(tycon):
            let type_var: ast.TypeVariable = ast.new_type_var(this.new_id())
            type_arguments.append(ast.new_type_var_ref(type_var))
        return ast.apply_tycon(tycon, type_arguments)
    
    fn new_id() -> int:
        this.counter += 1
        return this.counter
