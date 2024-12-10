"""
Type checking logic.
"""

import ast
from datatypes import Option, List, option_unwrap, option_is_none
from vectype import Vector
from strlib import str_join
from settype import new_str_set
from location import Location
from utils import log_info, panic, assert
from errors import CompilationError, new_errors, new_error, SingleCompilationError

pub fn type_check_modules(module_set: ast.ModuleSet) except CompilationError:
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
    ast.Visitor:
        data: checker
        on_definition: checker_on_definition
        on_type: checker_on_type
        on_statement: checker_on_statement
        on_expression: checker_on_expression
        on_node: checker_on_node

pub fn type_check_expression(expression: ast.Expression) except CompilationError:
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
                    checker.was_errors = false
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

fn assign_types(variables: List[ast.Variable], types: Vector[ast.Type]):
    let index = 0
    for v in variables:
        v.ty = types[index]
        index += 1

fn checker_on_statement(checker: TypeChecker, statement: ast.Statement, phase: ast.VisitPhase):
    if checker.was_errors:
        return
    case phase:
        Pre:
            if statement.is_breakable():
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
            if statement.is_breakable():
                checker.loops -= 1
    else:
        pass

fn checker_on_expression(checker: TypeChecker, expression: ast.Expression, phase: ast.VisitPhase):
    if checker.was_errors:
        return
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
    var m_void_type: ast.Type = ast.void_type()
    var m_bool_type: ast.Type = ast.bool_type()
    var m_int_type: ast.Type = ast.int_type()
    var m_str_type: ast.Type = ast.str_type()

    fn check_function_def(function_def: ast.FunctionDef):
        # Check if we return a value, if we need to return a value
        case function_def.body:
            Intern(scoped_block):
                if not was_errors:
                    if not scoped_block.body.ty.is_unreachable():
                        assert_statement_type(statement: scoped_block.body, ty: function_def.info.return_type)
            Extern(libname):
                pass

    fn check_statement_mid(statement: ast.Statement):
        case statement.kind:
            Case(case_statement):
                if case_statement.value.ty.is_enum():
                    let variant_names = case_statement.value.ty.get_enum_variant_names()
                    let uncovered_arms = new_str_set()
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
                        let parts: List[str] = List()
                        for uncovered_arm in uncovered_arms:
                            parts.append(uncovered_arm)
                        if parts.len() > 0:
                            let uncovered_text = str_join(parts, sep: ", ")
                            add_error(location: statement.location, message: "Enum cases not covered: {uncovered_text}")
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
                elif for_statement.iter_value.ty.is_str():
                    for_statement.iter_var.ty = ast.char_type()
                else:
                    add_error(location: for_statement.iter_value.location, message: "Value cannot be iterated: {for_statement.iter_value.ty}")
            Try(try_statement):
                exception_handlers.drop_last()
                try_statement.except_var.ty = try_statement.except_type
        else:
            pass

    fn check_statement(statement: ast.Statement):
        case statement.kind:
            Let(let_statement):
                case let_statement.type_hint:
                    Some(ty):
                        let_statement.variable.ty = ty
                    None:
                        let_statement.variable.ty = let_statement.value.ty
                coerce(ty: let_statement.variable.ty, value: let_statement.value)
                statement.ty = m_void_type
            Case(case_statement):
                let ty = ast.unreachable_type()
                for arm in case_statement.arms:
                    ty = merge_paths(statement: arm.block.body, ty)
                case case_statement.else_block:
                    Some(block):
                        ty = merge_paths(statement: block.body, ty)
                    None:
                        pass
                statement.ty = ty
            Switch(switch_statement):
                coerce(ty: m_int_type, value: switch_statement.value)
                let ty = switch_statement.default_block.body.ty
                for arm in switch_statement.arms:
                    ty = merge_paths(statement: arm.block.body, ty)
                statement.ty = ty
            Expr(expression):
                statement.ty = expression.ty
            If(if_statement):
                coerce(ty: m_bool_type, value: if_statement.condition)
                let ty = if_statement.true_block.body.ty
                ty = merge_paths(statement: if_statement.false_block.body, ty)
                statement.ty = ty
            For(for_statement):
                assert_void(statement: for_statement.block.body)
                statement.ty = m_void_type
            Loop(loop_statement):
                assert_void(statement: loop_statement.block.body)
                statement.ty = m_void_type
            While(while_statement):
                coerce(ty: m_bool_type, value: while_statement.condition)
                assert_void(statement: while_statement.block.body)
                statement.ty = m_void_type
            Assignment(target, op, value):
                coerce(ty: target.ty, value)
                statement.ty = m_void_type
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
                statement.ty = ast.unreachable_type()
            Raise(value):
                check_may_raise_exception(ty: value.ty, location: statement.location)
                statement.ty = ast.unreachable_type()
            Unreachable:
                statement.ty = ast.unreachable_type()
            Compound(inner):
                assert(condition: not inner.is_empty(), message: "Compound statement must not be empty.")
                let n = inner.len()
                let i = 0
                for x in inner:
                    i += 1
                    let is_last = i == n
                    if is_last:
                        statement.ty = x.ty
                    else:
                        assert_void(statement: x)
            Try(try_statement):
                assert_void(statement: try_statement.try_block.body)
                assert_void(statement: try_statement.except_block.body)
                statement.ty = m_void_type
            Break:
                if loops == 0:
                    add_error(location: statement.location, message: "Connot use break outside of a loop")
                statement.ty = ast.unreachable_type()
            Continue:
                if loops == 0:
                    add_error(location: statement.location, message: "Connot use continue outside of a loop")
                statement.ty = ast.unreachable_type()
            Pass:
                statement.ty = m_void_type

    fn check_expression(expression: ast.Expression):
        case expression.kind:
            Call(call):
                if call.callee.ty.is_function_type():
                    let parameter_types = call.callee.ty.get_parameter_types()
                    let return_type = call.callee.ty.get_return_type()

                    if parameter_types.len() == call.arguments.len():
                        let a_iter = call.arguments.iter()
                        for p_ty in parameter_types:
                            let argument = option_unwrap(a_iter.next())
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
                if ty.is_int():
                    if not (value.ty.is_int() or value.ty.is_float()):
                        add_error(location: expression.location, message: "Cannot cast to int from {value.ty}")
                elif ty.is_float():
                    if not (value.ty.is_int() or value.ty.is_float()):
                        add_error(location: expression.location, message: "Cannot cast to float from {value.ty}")
                else:
                    add_error(location: expression.location, message: "Cannot cast to {ty}")
                expression.ty = ty
            ToString(value):
                if not (value.ty.is_int() or value.ty.is_str() or value.ty.is_char() or value.ty.has_method("to_string")):
                    add_error(location: expression.location, message: "Cannot convert {value.ty} to string automatically")
                expression.ty = m_str_type
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
                    expression.ty = m_bool_type
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
                panic("symbols should be resolved: {symbol}")
            Variant(ty, v):
                add_error(location: expression.location, message: "variants must be literals")
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
                elif base.ty.is_str():
                    expression.ty = ast.char_type()
                else:
                    add_error(location: expression.location, message: "Got {base.ty}, expected array or indexable type")

                if indici.len() == 1:
                    let index: ast.Expression = indici.first()
                    coerce(ty: m_int_type, value: index)
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
                coerce(ty: ast.opaque_type(), value)
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
            ArrayLiteral2(size, element_type):
                expression.ty = ast.array_type(element_type, size: 0)
            StringLiteral(s):
                expression.ty = m_str_type
            CharLiteral(s):
                expression.ty = ast.char_type()
            BoolLiteral(b):
                expression.ty = m_bool_type
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
                expression.ty = m_int_type
            FloatLiteral(b):
                expression.ty = ast.float_type()
            Stmt(statement):
                expression.ty = statement.ty

    fn check_arguments(location: Location, parameter_types: Vector[ast.Type], arguments: List[ast.Expression]):
        if parameter_types.len() == arguments.len():
            let index = 0
            for argument in arguments:
                let p_ty = parameter_types[index]
                coerce(ty: p_ty, value: argument)
                index += 1
        else:
            add_error(location, message: "got {arguments.len()} arguments, expected {parameter_types.len()}")

    fn check_may_raise_exception(ty: ast.Type, location: Location):
        if exception_handlers.is_empty():
            add_error(location, message: "Cannot raise exception here")
        else:
            let expected_exception_type = exception_handlers.last()
            if not unify(ty1: ty, ty2: expected_exception_type):
                add_error(location, message: "Raised {ty}, expected: {expected_exception_type}")

    fn assert_void(statement: ast.Statement):
        if not statement.ty.is_unreachable():
            check_type(given_ty: statement.ty, expected_ty: m_void_type, location: statement.location)

    fn assert_statement_type(statement: ast.Statement, ty: ast.Type):
        check_type(given_ty: statement.ty, expected_ty: ty, location: statement.location)

    fn merge_paths(statement: ast.Statement, ty: ast.Type) -> ast.Type:
        if statement.ty.is_unreachable():
            ty
        elif ty.is_unreachable():
            statement.ty
        else:
            check_type(given_ty: statement.ty, expected_ty: ty, location: statement.location)
            ty

    fn coerce(ty: ast.Type, value: ast.Expression):
        """ Fit an expression to a type. """
        # Try to auto-convert before check:
        if value.ty.is_int() and ty.is_float():
            # Auto-conv int to floats
            let old_expr = ast.clone_expression(value)
            value.kind = ast.ExpressionKind.TypeCast(ty, old_expr)
            value.ty = ty

        check_type(given_ty: value.ty, expected_ty: ty, location: value.location)
    
    fn check_type(given_ty: ast.Type, expected_ty: ast.Type, location: Location):
        if not unify(ty1: given_ty, ty2: expected_ty):
            add_error(location, message: "Got {given_ty}, expected {expected_ty}")

    fn unify(ty1: ast.Type, ty2: ast.Type) -> bool:
        if ty1.is_base_type() and ty2.is_base_type():
            let base_type1 = ty1.get_base_type()
            let base_type2 = ty2.get_base_type()
            ast.base_type_equal(base_type1, base_type2)
        elif ty1.is_opaque() and ty2.is_opaque():
            true
        elif ty1.is_void() and ty2.is_void():
            true
        elif ty1.is_base_type() and ast.is_some_integer_type(ty2):
            let base_type1 = ty1.get_base_type()
            let needed_bits = ast.get_bits_from_some_integer_type(ty2)
            case base_type1:
                Int(signed, bits):
                    if needed_bits <= bits:
                        ty2.change_to(to_type: ty1)
                        true
                    else:
                        false
            else:
                false
        elif ast.is_some_integer_type(ty1) and ty2.is_base_type():
            unify(ty1: ty2, ty2: ty1)  # Invoke swapped
        elif ty1.is_tycon_app() and ty2.is_tycon_app():
            let tycon1 = ty1.get_tycon()
            let tycon2 = ty2.get_tycon()
            if ast.tycon_equal(tycon1, tycon2):
                let type_arguments1 = ty1.get_type_arguments()
                let type_arguments2 = ty2.get_type_arguments()
                unify_many(typs1: type_arguments1, typs2: type_arguments2)
            else:
                false
        elif ty1.is_type_parameter() and ty2.is_type_parameter():
            let tp1 = ty1.get_type_parameter()
            let tp2 = ty2.get_type_parameter()
            ast.type_parameter_equals(tp1, tp2)
        elif ty1.is_function_type() and ty2.is_function_type():
            let ptys1 = ast.get_types_from_parameter_types(ty1.get_parameter_types())
            let ptys2 = ast.get_types_from_parameter_types(ty2.get_parameter_types())

            if not unify_many(typs1: ptys1, typs2: ptys2):
                return false
            
            let rty1 = ty1.get_return_type()
            let rty2 = ty2.get_return_type()
            if not unify(ty1: rty1, ty2: rty2):
                return false

            true
        elif ty1.is_array() and ty2.is_array():
            unify(ty1: ty1.get_element_type(), ty2: ty2.get_element_type())
        elif ty1.is_type_var():
            let type_var1: ast.TypeVariable = ty1.get_type_var()
            case type_var1.ty:
                None:
                    if ty2.is_type_var():
                        let type_var2: ast.TypeVariable = ty2.get_type_var()
                        case type_var2.ty:
                            None:
                                ast.type_var_equals(type_var1, type_var2)
                            Some(assigned_ty):
                                type_var1.ty = Option.Some(assigned_ty)
                                ty1.change_to(to_type: assigned_ty)
                                true
                    else:
                        type_var1.ty = Option.Some(ty2)
                        ty1.change_to(to_type: ty2)
                        true
                Some(assigned_ty):
                    ty1.change_to(to_type: assigned_ty)
                    unify(ty1, ty2)
        elif ty2.is_type_var():
            unify(ty1: ty2, ty2: ty1)
        elif ty1.is_unreachable() and ty2.is_unreachable():
            true
        else:
            false
    
    fn unify_many(typs1: Vector[ast.Type], typs2: Vector[ast.Type]) -> bool:
        if typs1.len() == typs2.len():
            let n = typs1.len()
            let index = 0
            while index < n:
                let ty1 = typs1[index]
                let ty2 = typs2[index]
                if not unify(ty1, ty2):
                    return false
                index += 1
            true
        else:
            false

    fn add_error(location: Location, message: str):
        # This can be handy if type checking fails half way:
        # log_error(message)
        let err = new_error(location, message)
        errors.append(err)
        was_errors = true
