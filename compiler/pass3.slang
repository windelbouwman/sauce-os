
import ast
from std import print
from location import Location
from basepass import IdGen
from utils import log_info, panic
from errors import new_error, new_errors, CompilationError, SingleCompilationError
from datatypes import Dictionary, List, Option


fn resolve_newops(module: ast.Module, id_gen: IdGen) except CompilationError:
    log_info("resolve new-ops for {module.name}")
    let newop = NewOp(id_gen)
    let visitor = ast.Visitor[NewOp]:
        data: newop
        on_definition: newop_on_definition
        on_type: newop_on_type
        on_statement: newop_on_statement
        on_expression: newop_on_expression
        on_node: newop_on_node
    ast.visit_module(visitor, module)
    if not newop.errors.is_empty():
        raise new_errors(filename: module.filename, errors: newop.errors)

fn newop_on_definition(newop: NewOp, definition: ast.Definition, phase: ast.VisitPhase):
    pass

fn newop_on_type(newop: NewOp, ty: ast.Type, phase: ast.VisitPhase):
    case phase:
        Post:
            case ty.kind:
                TypeExpression(expression):
                    ast.change_type_to(ty, ty2: newop.eval_type_expr(expression))
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
                #ObjInit(ty, labeled_fields):
                    
                GetIndex(base, indici):
                    case base.kind:
                        TypeConstructor(tycon):
                            let type_arguments: List[ast.Type] = List()
                            for index in indici:
                                type_arguments.append(newop.eval_type_expr(expression: index))
                            let ty = ast.apply_tycon(tycon, type_arguments)
                            expression.kind = ast.ExpressionKind.Typ(ty)
                    else:
                        pass

                GetAttr(base, attr):
                    case newop.try_as_type(expression: base):
                        Some(ty):
                            if ast.is_enum_type(ty):
                                case ast.get_enum_variant_from_type(ty, attr):
                                    Some(variant):
                                        expression.kind = ast.ExpressionKind.Variant(ty, variant)
                                    None:
                                        newop.add_error(location: expression.location, message: "No such enum variant: {attr}")
                                    
                            else:
                                newop.add_error(location: expression.location, message: "Can only get attr from enum type, not {ast.type_to_string(ty)}")
                        None:
                            pass
                    
                Call(call):
                    case call.callee.kind:
                        Variant(ty, variant):
                            let values: List[ast.Expression] = List()
                            for argument in call.arguments:
                                values.append(argument.value)
                            expression.kind = ast.ExpressionKind.EnumLiteral(ty, variant, values)
                    else:
                        case newop.try_as_type(expression: call.callee):
                            Some(ty):
                                let value_map: Dictionary[ast.Expression] = Dictionary()
                                for labeled_field in call.arguments:
                                    case labeled_field.name:
                                        Some(field_name3):
                                            if value_map.contains(key: field_name3):
                                                newop.add_error(location: labeled_field.location, message: "Duplicate field: {field_name3}")
                                            else:
                                                value_map.insert(key: field_name3, value: labeled_field.value)
                                        None:
                                            newop.add_error(location: labeled_field.location, message: "Unlabeled expression")
                                
                                # Check that type is struct?
                                let ok = false
                                case ty.kind:
                                    App(tycon, type_arguments):
                                        case tycon:
                                            Struct(struct_def):
                                                ok = true
                                                let values: List[ast.Expression] = List()
                                                for field in struct_def.fields:
                                                    case value_map.pop(key: field.name):
                                                        Some(v):
                                                            values.append(v)
                                                        None:
                                                            newop.add_error(location: expression.location, message: "Missing field: {field.name}")
                                                
                                                for name in value_map:
                                                    newop.add_error(location: expression.location, message: "Superfluous field: {name}")

                                                expression.kind = ast.ExpressionKind.StructLiteral(ty, values)
                                            Class(class_def):
                                                ok = true
                                                # TODO: check arguments
                                                expression.kind = ast.ExpressionKind.ClassLiteral(ty, arguments: call.arguments)
                                        else:
                                            pass
                                    Float:
                                        ok = true
                                        # TODO: check arguments
                                        let value = call.arguments.first().value
                                        expression.kind = ast.ExpressionKind.TypeCast(ty, value)
                                else:
                                    pass

                                if not ok:
                                    newop.add_error(location: expression.location, message: "Cannot call type: {ast.type_to_string(ty)}")
                            None:
                                pass
                LoadSymbol(symbol):
                    case symbol:
                        Function(function_def):

                            # Ha, create type variables!
                            let type_arguments: List[ast.Type] = List()
                            for tp in function_def.type_parameters:
                                let type_var = ast.new_type_var(unique: newop.new_id())
                                let type_arg = ast.new_type_var_ref(type_var)
                                type_arg.was_generic = true
                                type_arguments.append(type_arg)

                            expression.kind = ast.ExpressionKind.FunctionRef(function_def, type_arguments)
                    else:
                        pass
            else:
                pass
    else:
        pass

fn newop_on_node(newop: NewOp, node: ast.VisitNode, phase: ast.VisitPhase):
    pass

class NewOp:
    var errors: List[SingleCompilationError] = List()
    var id_gen: IdGen

    fn try_as_type(expression: ast.Expression) -> Option[ast.Type]:
        # Try to use this expression as a type.
        case expression.kind:
            Typ(ty2):
                return Option.Some(ty2)
            TypeConstructor(tycon):
                let ty2 = this.turn_tycon_to_type(tycon)
                return Option.Some(ty2)
        else:
            return Option.None()

    fn eval_type_expr(expression: ast.Expression) -> ast.Type:
        # Try to use this expression as a type.
        case this.try_as_type(expression):
            Some(ty2):
                return ty2
            None:
                let message = "Invalid type expression: {ast.expression_to_string(expression)}"
                this.add_error(location: expression.location, message)
                return ast.undefined_type()

    fn add_error(location: Location, message: str):
        this.errors.append(new_error(location, message))
    
    fn turn_tycon_to_type(tycon: ast.TyCon) -> ast.Type:
        let type_arguments: List[ast.Type] = List()
        for tp in ast.tycon_get_type_parameters(tycon):
            let type_var: ast.TypeVariable = ast.new_type_var(unique: this.new_id())
            type_arguments.append(ast.new_type_var_ref(type_var))
        return ast.apply_tycon(tycon, type_arguments)
    
    fn new_id() -> int:
        return this.id_gen.new_id()
