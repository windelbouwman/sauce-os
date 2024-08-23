
# Type checking logic.

import ast
from math import ceil, log2
from std import print
from datatypes import Option, List, option_unwrap, option_is_none
from settype import Set
from location import Location, location_to_string
from utils import log_info, panic, log_error
from errors import CompilationError, new_errors, new_error, display_error, SingleCompilationError

fn type_check_modules(module_set: ast.ModuleSet) except CompilationError:
    for module in module_set.modules:
        type_check(module)

fn type_check(module: ast.Module) except CompilationError:
    log_info("Checking module {module.name}")
    let checker = TypeChecker()
    let visitor = new_type_check_visitor(checker)
    ast.visit_module(visitor, module)
    if not checker.errors.is_empty():
        raise new_errors(filename: module.filename, errors: checker.errors)

fn new_type_check_visitor(checker: TypeChecker) -> ast.Visitor[TypeChecker]:
    let visitor = ast.Visitor:
        data: checker
        on_definition: checker_on_definition
        on_type: checker_on_type
        on_statement: checker_on_statement
        on_expression: checker_on_expression
        on_node: checker_on_node
    return visitor

fn type_check_expression(expression: ast.Expression) except CompilationError:
    let checker = TypeChecker()
    let visitor = new_type_check_visitor(checker)
    ast.visit_expression(visitor, expression)
    if not checker.errors.is_empty():
        raise new_errors(filename: Option.None(), errors: checker.errors)

fn checker_on_definition(checker: TypeChecker, definition: ast.Definition, phase: ast.VisitPhase):
    case phase:
        Pre:
            case definition:
                Function(function_def):
                    checker.current_function = Option.Some(function_def)
                    if not function_def.info.except_type.is_void():
                        checker.exception_handlers.append(function_def.info.except_type)
            else:
                pass
        Post:
            case definition:
                Function(function_def):
                    checker.check_function_def(function_def)
                    checker.current_function = Option.None()
                    if not function_def.info.except_type.is_void():
                        checker.exception_handlers.drop_last()
            else:
                pass
    else:
        pass

fn checker_on_type(checker: TypeChecker, ty: ast.Type, phase: ast.VisitPhase):
    pass

fn assign_types(variables: List[ast.Variable], types: List[ast.Type]):
    let pi = types.iter()
    for v in variables:
        let ty = option_unwrap(pi.next())
        v.ty = ty

fn checker_on_statement(checker: TypeChecker, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Pre:
            checker.was_errors = false
            if ast.is_breakable(statement):
                checker.loops += 1
            case statement.kind:
                Try(try_statement):
                    checker.exception_handlers.append(try_statement.except_type)
            else:
                pass
        Mid:
            checker.check_statement_mid(statement)
        Post:
            checker.check_statement(statement)
            if ast.is_breakable(statement):
                checker.loops -= 1
    else:
        pass

fn checker_on_expression(checker: TypeChecker, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            checker.check_expression(expression)
    else:
        pass


fn checker_on_node(checker: TypeChecker, node: ast.VisitNode, phase: ast.VisitPhase):
    pass

class TypeChecker:
    var errors: List[SingleCompilationError] = List()
    var was_errors: bool = false
    var current_function: Option[ast.FunctionDef] = Option.None()
    var loops: int = 0
    var exception_handlers: List[ast.Type] = List()

    fn check_function_def(function_def: ast.FunctionDef):
        # Check if we return a value, if we need to return a value
        case function_def.body:
            Intern(scoped_block):
                if not function_def.info.return_type.is_void():
                    if not scoped_block.body.is_terminator:
                        add_error(location: function_def.location, message: "Control reaches end of non-void function")
            Extern(libname):
                pass

    fn check_statement_mid(statement: ast.Statement):
        case statement.kind:
            Case(case_statement):
                if case_statement.value.ty.is_enum():
                    let variant_names = ast.get_enum_variant_names_from_type(case_statement.value.ty)
                    let uncovered_arms = Set()
                    for variant_name in variant_names:
                        uncovered_arms.add(variant_name)
                    for arm in case_statement.arms:
                        case case_statement.value.ty.get_enum_variant_from_type(attr: arm.name):
                            Some(variant):
                                if uncovered_arms.contains(arm.name):
                                    uncovered_arms.remove(arm.name)
                                    let payload_types = ast.get_variant_payload_types(ty: case_statement.value.ty, variant)
                                    if payload_types.len() == arm.variables.len():
                                        assign_types(variables: arm.variables, types: payload_types)
                                    else:
                                        add_error(location: arm.location, message: "Got {arm.variables.len()}, expected {payload_types.len()} values")
                                    # expression.kind = ast.ExpressionKind.Variant(ty3, variant)
                                else:
                                    add_error(location: arm.location, message: "Enum case covered twice")
                            None:
                                add_error(location: arm.location, message: "No such enum variant: {arm.name}")
                    if option_is_none(case_statement.else_block):
                        for uncovered_arm in uncovered_arms:
                            add_error(location: statement.location, message: "Enum case not covered: {uncovered_arm}")
                else:
                    add_error(location: case_statement.value.location, message: "Got {case_statement.value.ty}, expected enum")
            For(for_statement):
                if for_statement.iter_value.ty.is_array():
                    let size = for_statement.iter_value.ty.get_array_size()
                    if size > 0:
                        for_statement.iter_var.ty = for_statement.iter_value.ty.get_element_type()
                    else:
                        add_error(location: for_statement.iter_value.location, message: "Array size unknown")
                elif for_statement.iter_value.ty.is_iterable_like():
                    # TODO: we have a few assumptions here, which panic. Should be proper warning:
                    let iter_ty: ast.Type = for_statement.iter_value.ty.get_field_type(attr: "iter").get_return_type()
                    let opt_ty: ast.Type = iter_ty.get_field_type(attr: "next").get_return_type()
                    let opt_variant = option_unwrap(opt_ty.get_enum_variant_from_type(attr: "Some"))
                    let val_ty: ast.Type = ast.get_variant_payload_types(ty: opt_ty, variant: opt_variant).first()
                    for_statement.iter_var.ty = val_ty
                elif for_statement.iter_value.ty.is_sequence_like():
                    let val_ty: ast.Type = for_statement.iter_value.ty.get_field_type(attr: "get").get_return_type()
                    for_statement.iter_var.ty = val_ty
                else:
                    add_error(location: for_statement.iter_value.location, message: "Value cannot be iterated: {for_statement.iter_value.ty}")
            Try(try_statement):
                exception_handlers.drop_last()
                try_statement.except_var.ty = try_statement.except_type
        else:
            pass

    fn check_statement(statement: ast.Statement):
        if was_errors:
            return

        case statement.kind:
            Let(let_statement):
                case let_statement.type_hint:
                    Some(ty):
                        let_statement.variable.ty = ty
                    None:
                        let_statement.variable.ty = let_statement.value.ty
                coerce(ty: let_statement.variable.ty, value: let_statement.value)
            Case(case_statement):
                statement.is_terminator = true
                for arm in case_statement.arms:
                    if not arm.block.body.is_terminator:
                        statement.is_terminator = false
                case case_statement.else_block:
                    Some(block):
                        if not block.body.is_terminator:
                            statement.is_terminator = false
                    None:
                        pass
            Expr(expression):
                # Check we are of void type.
                if not expression.ty.is_void():
                    add_error(location: expression.location, message: "Non-void expression")

                case expression.kind:
                    Call(call):
                        case call.callee.kind:
                            FunctionRef(function_def, type_arguments):
                                statement.is_terminator = function_def.info.no_return
                        else:
                            statement.is_terminator = false
                else:
                    statement.is_terminator = false
            If(if_statement):
                coerce(ty: ast.bool_type(), value: if_statement.condition)
                statement.is_terminator = if_statement.true_block.body.is_terminator and if_statement.false_block.body.is_terminator
            While(while_statement):
                coerce(ty: ast.bool_type(), value: while_statement.condition)
                statement.is_terminator = false
            Assignment(target, op, value):
                coerce(ty: target.ty, value)
                statement.is_terminator = false
            Return(value):
                let func = option_unwrap(current_function)
                case value:
                    Some(value):
                        if func.info.return_type.is_void():
                            add_error(location: value.location, message: "Unexpected return value")
                        else:
                            coerce(ty: func.info.return_type, value)
                    None:
                        if not func.info.return_type.is_void():
                            add_error(location: statement.location, message: "Expected a value")
                statement.is_terminator = true
            Raise(value):
                check_may_raise_exception(ty: value.ty, location: statement.location)
                statement.is_terminator = true
            Unreachable:
                statement.is_terminator = true
            Compound(x):
                if x.is_empty():
                    statement.is_terminator = false
                else:
                    statement.is_terminator = x.last().is_terminator
            Try(try_statement):
                if not try_statement.try_block.body.is_terminator:
                    statement.is_terminator = false
                elif not try_statement.except_block.body.is_terminator:
                    statement.is_terminator = false
                else:
                    statement.is_terminator = true
            Break:
                if loops == 0:
                    add_error(location: statement.location, message: "Connot use break outside of a loop")
            Continue:
                if loops == 0:
                    add_error(location: statement.location, message: "Connot use continue outside of a loop")
        else:
            pass

    fn check_expression(expression: ast.Expression):
        if was_errors:
            return

        case expression.kind:
            Call(call):
                if call.callee.ty.is_function_type():
                    let parameter_types = ast.get_parameter_types_from_type(call.callee.ty)
                    let return_type = call.callee.ty.get_return_type()

                    if parameter_types.len() == call.arguments.len():
                        let p_iter = parameter_types.iter()
                        for argument in call.arguments:
                            let p_ty = option_unwrap(p_iter.next())
                            coerce(ty: p_ty.ty, value: argument.value)

                            # Check named arguments:
                            case p_ty.label:
                                Some(label):
                                    case argument.name:
                                        Some(name):
                                            if not (label == name):
                                                add_error(location: argument.location, message: "Got label '{name}', expected label '{label}'")
                                        None:
                                            add_error(location: argument.location, message: "Expected a labeled argument '{label}'")
                                None:
                                    pass

                    else:
                        add_error(location: expression.location, message: "got {call.arguments.len()} arguments, expected {parameter_types.len()}")

                    if was_errors:
                        return

                    expression.ty = ast.deref_type_var(return_type)
                    # print("Call: {expression.ty}")

                    # Check exception raising:
                    let except_type = call.callee.ty.get_except_type()
                    if not except_type.is_void():
                        check_may_raise_exception(ty: except_type, location: expression.location)
                else:
                    add_error(location: expression.location, message: "Cannot call non-function type {call.callee.ty}")
            ParameterRef(parameter_def):
                # TODO: clone type?
                # log_trace("Parameter {ast.node_id_to_string(parameter.id)}: {parameter.ty}")
                expression.ty = parameter_def.ty
            VarRef(variable):
                # log_trace("Var ref {ast.node_id_to_string(variable.id)}: {variable.ty}")
                expression.ty = variable.ty
            FunctionRef(function_def, type_arguments):
                expression.ty = ast.get_function_type2(function_def, type_arguments)
            TypeConstructor(tycon):
                add_error(location: expression.location, message: "Cannot use a type constructor here")
            TypeCast(ty, value):
                expression.ty = ty
            ToString(value):
                if not (value.ty.is_int() or value.ty.is_str() or value.ty.is_char() or value.ty.has_method("to_string")):
                    add_error(location: expression.location, message: "Cannot convert {value.ty} to string automatically")
                expression.ty = ast.str_type()
            Typ(t):
                add_error(location: expression.location, message: "Cannot use a type here")
            Binop(binop):
                # Heuristics ahead...
                let ty = binop.lhs.ty
                let rhs_ty = binop.rhs.ty
                if ty.is_int() and rhs_ty.is_float():
                    ty = rhs_ty

                coerce(ty, value: binop.lhs)
                coerce(ty, value: binop.rhs)
                if ast.is_comparison_op(op: binop.op):
                    expression.ty = ast.bool_type()
                else:
                    expression.ty = ty
            Unop(op, rhs):
                case op:
                    Minus:
                        let ty = rhs.ty
                        if ty.is_float() or ty.is_int():
                            expression.ty = ty
                        else:
                            add_error(location: expression.location, message: "Got {ty}, but unary '-' requires numeric type")
                    Not:
                        let ty = rhs.ty
                        if ty.is_bool():
                            expression.ty = ty
                        else:
                            add_error(location: expression.location, message: "Got {ty}, but 'not' operator requires bool type")
            NameRef(name):
                panic("names must be resolved: {name}")
            LoadSymbol(symbol):
                panic("symbols should be resolved: {ast.symbol_to_str(symbol)}")
            Variant(ty, v):
                add_error(location: expression.location, message: "variants must be literals")
            Undefined:
                panic("check_expression: undefined")
            Null:
                pass
            GetAttr(base, attr):
                case base.ty.maybe_get_field_type(attr):
                    Some(ty):
                        expression.ty = ty
                    None:
                        add_error(location: expression.location, message: "Type {base.ty} has no field: {attr}")
                        expression.ty = ast.undefined_type()
            GetIndex(base, indici):
                if base.ty.is_array():
                    expression.ty = base.ty.get_element_type()
                elif base.ty.has_method("get"):
                    # Maybe we try to access an object with get/set interface
                    # TODO: we have a few assumptions here, which panic. Should be proper warning:
                    let val_ty: ast.Type = base.ty.get_field_type(attr: "get").get_return_type()
                    expression.ty = val_ty
                else:
                    add_error(location: expression.location, message: "Got {base.ty}, expected array or indexable type")

                if indici.len() == 1:
                    let index: ast.Expression = indici.first()
                    coerce(ty: ast.int_type(), value: index)
                else:
                    add_error(location: expression.location, message: "Only 1 dimensional indexing supported.")
            EnumLiteral(ty, variant, values):
                let payload_types = ast.get_variant_payload_types(ty, variant)
                check_arguments(location: expression.location, parameter_types: payload_types, arguments: values)
                expression.ty = ty
            ClassLiteral(ty, arguments):
                # TODO: check arguments
                expression.ty = ty
            StructLiteral(ty, values):
                let field_types = ty.get_field_types()
                check_arguments(location: expression.location, parameter_types: field_types, arguments: values)
                expression.ty = ty
            UnionLiteral(ty, field, value):
                let wanted_value_type = ty.get_field_type(attr: field)
                coerce(ty: wanted_value_type, value)
                expression.ty = ty
            Box(value):
                expression.ty = ast.opaque_type()
            Unbox(value, to_type):
                expression.ty = to_type
            ArrayLiteral(values):
                let element_type: ast.Type = values.first().ty

                # Check all types are equal!
                let skip = true
                for value in values:
                    # we can skip the first item
                    if skip:
                        skip = false
                    else:
                        coerce(ty: element_type, value)

                expression.ty = ast.array_type(element_type, size: values.len())
            ArrayLiteral2(value, size):
                let element_type = value.ty
                expression.ty = ast.array_type(element_type, size: 0)
            StringLiteral(s):
                expression.ty = ast.str_type()
            CharLiteral(s):
                expression.ty = ast.char_type()
            BoolLiteral(b):
                expression.ty = ast.bool_type()
            IntLiteral(i):
                # Calculate how many bits we require to store this literal:
                # let bits = 1
                # if i > 0:
                #     bits = int(value: ceil(log2(i))) + 1
                # elif i < 0:
                #     bits = int(value: ceil(log2(-i))) + 2
                # else:  # i = 0, 1 bit required.
                #     bits = 1
                # expression.ty = ast.some_int_type(bits)
                expression.ty = ast.int_type()
            FloatLiteral(b):
                expression.ty = ast.float_type()

    fn check_arguments(location: Location, parameter_types: List[ast.Type], arguments: List[ast.Expression]):
        if parameter_types.len() == arguments.len():
            let p_iter = parameter_types.iter()
            for argument in arguments:
                let p_ty = option_unwrap(p_iter.next())
                coerce(ty: p_ty, value: argument)
        else:
            add_error(location, message: "got {arguments.len()} arguments, expected {parameter_types.len()}")

    fn check_may_raise_exception(ty: ast.Type, location: Location):
        if exception_handlers.is_empty():
            add_error(location, message: "Cannot raise exception here")
        else:
            let expected_exception_type = exception_handlers.last()
            if not unify(ty1: ty, ty2: expected_exception_type):
                add_error(location, message: "Raised {ty}, expected: {expected_exception_type}")

    fn coerce(ty: ast.Type, value: ast.Expression):
        # Try to auto-convert before check:
        if value.ty.is_int() and ty.is_float():
            # Auto-conv int to floats
            let old_expr = ast.clone_expression(value)
            value.kind = ast.ExpressionKind.TypeCast(ty, old_expr)
            value.ty = ty

        if not unify(ty1: value.ty, ty2: ty):
            add_error(location: value.location, message: "Got {value.ty}, expected {ty}")
    
    fn unify(ty1: ast.Type, ty2: ast.Type) -> bool:
        if ty1.is_base_type() and ty2.is_base_type():
            let base_type1 = ty1.get_base_type()
            let base_type2 = ty2.get_base_type()
            return ast.base_type_equal(base_type1, base_type2)
        elif ty1.is_opaque() and ty2.is_opaque():
            return true
        elif ty1.is_void() and ty2.is_void():
            return true
        elif ty1.is_base_type() and ast.is_some_integer_type(ty2):
            let base_type1 = ty1.get_base_type()
            let needed_bits = ast.get_bits_from_some_integer_type(ty2)
            case base_type1:
                Int(signed, bits):
                    if needed_bits <= bits:
                        ast.change_type_to(ty: ty2, to_type: ty1)
                        return true
                    else:
                        return false
            else:
                return false
        elif ast.is_some_integer_type(ty1) and ty2.is_base_type():
            return unify(ty1: ty2, ty2: ty1)  # Invoke swapped
        elif ty1.is_tycon_app() and ty2.is_tycon_app():
            let tycon1 = ty1.get_tycon()
            let tycon2 = ty2.get_tycon()
            if ast.tycon_equal(tycon1, tycon2):
                let type_arguments1 = ty1.get_type_arguments()
                let type_arguments2 = ty2.get_type_arguments()
                return unify_many(typs1: type_arguments1, typs2: type_arguments2)
            else:
                return false
        elif ty1.is_type_parameter() and ty2.is_type_parameter():
            let tp1 = ty1.get_type_parameter()
            let tp2 = ty2.get_type_parameter()
            return ast.type_parameter_equals(tp1, tp2)
        elif ty1.is_function_type() and ty2.is_function_type():
            let ptys1 = ast.get_types_from_parameter_types(ast.get_parameter_types_from_type(ty1))
            let ptys2 = ast.get_types_from_parameter_types(ast.get_parameter_types_from_type(ty2))

            if not unify_many(typs1: ptys1, typs2: ptys2):
                return false
            
            let rty1 = ty1.get_return_type()
            let rty2 = ty2.get_return_type()
            if not unify(ty1: rty1, ty2: rty2):
                return false

            return true
        elif ty1.is_array() and ty2.is_array():
            return unify(ty1: ty1.get_element_type(), ty2: ty2.get_element_type())
        elif ast.is_type_var_type(ty1):
            let type_var1: ast.TypeVariable = ast.get_type_var_from_type(ty1)
            case type_var1.ty:
                None:
                    if ast.is_type_var_type(ty2):
                        let type_var2: ast.TypeVariable = ast.get_type_var_from_type(ty2)
                        return ast.type_var_equals(type_var1, type_var2)
                    else:
                        type_var1.ty = Option.Some(ty2)
                        ty1.change_to(to_type: ty2)
                        return true
                Some(assigned_ty):
                    ty1.change_to(to_type: assigned_ty)
                    return unify(ty1, ty2)
        elif ast.is_type_var_type(ty2):
            return unify(ty1: ty2, ty2: ty1)
        else:
            return false
    
    fn unify_many(typs1: List[ast.Type], typs2: List[ast.Type]) -> bool:
        if typs1.len() == typs2.len():
            let typs2_it = typs2.iter()
            for ty1 in typs1:
                let ty2 = option_unwrap(typs2_it.next())
                if not unify(ty1, ty2):
                    return false
            return true
        else:
            return false

    fn add_error(location: Location, message: str):
        # This can be handy if type checking fails half way:
        # log_error(message)
        let err = new_error(location, message)
        errors.append(err)
        was_errors = true

