
import ast
from location import Location
from basepass import IdGen
from utils import log_info, panic
from errors import new_error, new_errors, CompilationError, SingleCompilationError
from datatypes import List, Option
from hashmap import HashMap, new_hashmap_str
from vectype import Vector, new_vector, new_vector_with_capacity

pub fn resolve_newops(module: ast.Module, id_gen: IdGen) except CompilationError:
    log_info("resolve new-ops for {module.name}")
    let newop = NewOp(id_gen)
    let visitor: ast.Visitor[NewOp] = ast.Visitor:
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
                UnApp(tycon):
                    ty.change_to(to_type: newop.turn_tycon_to_type(tycon))
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
                GetAttr(base, attr):
                    case base.kind:
                        Typ(ty):
                            if ty.is_enum():
                                case ty.get_enum_variant_from_type(attr):
                                    Some(variant):
                                        expression.kind = ast.ExpressionKind.Variant(ty, variant)
                                    None:
                                        newop.add_error(location: expression.location, message: "No such enum variant: {attr}")
                                    
                            else:
                                newop.add_error(location: expression.location, message: "Can only get attr from enum type, not {ty}")
                    else:
                        pass
                Call(call):
                    case call.callee.kind:
                        Variant(ty, variant):
                            let values: List[ast.Expression] = List()
                            for argument in call.arguments:
                                values.append(argument.value)
                            expression.kind = ast.ExpressionKind.EnumLiteral(ty, variant, values)
                        Typ(ty):
                            # Check that type is struct?
                            let ok = false
                            case ty.kind:
                                App(tycon, type_arguments):
                                    let value_map: HashMap[str,ast.Expression] = new_hashmap_str()
                                    for labeled_field in call.arguments:
                                        case labeled_field.name:
                                            Some(field_name3):
                                                if value_map.contains(key: field_name3):
                                                    newop.add_error(location: labeled_field.location, message: "Duplicate field: {field_name3}")
                                                else:
                                                    value_map.insert(key: field_name3, value: labeled_field.value)
                                            None:
                                                newop.add_error(location: labeled_field.location, message: "Unlabeled expression")

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
                                            expression.kind = ast.ExpressionKind.ClassLiteral(ty, arguments: call.arguments)
                                    else:
                                        pass
                                Base(base):
                                    case base:
                                        Float(bits):
                                            ok = true
                                        Int(signed, bits):
                                            ok = true
                                        Str:
                                            ok = true
                                    else:
                                        pass

                                    if ok:
                                        if call.arguments.len() == 1:
                                            let value = call.arguments.first().value
                                            case base:
                                                Str:
                                                    expression.kind = ast.ExpressionKind.ToString(value)
                                            else:
                                                expression.kind = ast.ExpressionKind.TypeCast(ty, value)
                                        else:
                                            newop.add_error(location: expression.location, message: "Expect exactly 1 argument to type cast")
                            else:
                                pass

                            if not ok:
                                newop.add_error(location: expression.location, message: "Cannot call type: {ty}")
                            
                    else:
                        pass
                LoadSymbol(symbol):
                    case symbol.kind:
                        Function(function_def):
                            # Ha, create type variables!
                            let type_arguments = newop.new_type_arguments(type_parameters: function_def.type_parameters)
                            expression.kind = ast.ExpressionKind.FunctionRef(function_def, type_arguments)

                    else:
                        panic("All symbols must be handled by now.")
            else:
                pass
    else:
        pass

fn newop_on_node(newop: NewOp, node: ast.VisitNode, phase: ast.VisitPhase):
    pass

class NewOp:
    pub var errors: List[SingleCompilationError] = List()
    var id_gen: IdGen

    fn try_as_type(expression: ast.Expression) -> Option[ast.Type]:
        # Try to use this expression as a type.
        case expression.kind:
            Typ(ty2):
                Option.Some(ty2)
        else:
            Option.None()

    pub fn add_error(location: Location, message: str):
        errors.append(new_error(location, message))
    
    pub fn turn_tycon_to_type(tycon: ast.TyCon) -> ast.Type:
        let type_arguments: Vector[ast.Type] = new_vector()
        for tp in ast.tycon_get_type_parameters(tycon):
            let type_var: ast.TypeVariable = ast.new_type_var(unique: new_id())
            type_arguments.append(ast.new_type_var_ref(type_var))
        ast.apply_tycon(tycon, type_arguments)
    
    pub fn new_type_arguments(type_parameters: List[ast.TypeParameter]) -> Vector[ast.Type]:
        let type_arguments: Vector[ast.Type] = new_vector_with_capacity(capacity: type_parameters.len())
        for tp in type_parameters:
            let type_var = ast.new_type_var(unique: new_id())
            let type_arg = ast.new_type_var_ref(type_var)
            type_arg.was_generic = true
            type_arguments.append(type_arg)
        type_arguments

    fn new_id() -> int:
        id_gen.new_id()
