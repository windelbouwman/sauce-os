
# Type checking logic.

import ast
from std import print
from datatypes import Option, List, option_unwrap
from location import Location
from utils import log_info, panic
from errors import CompilationError, new_errors, new_error, display_error

fn type_check(module: ast.Module) except CompilationError:
    log_info("Checking module {module.name}")

    let checker = TypeChecker()
    let check_visitor = ast.Visitor:
        data: checker
        on_definition: checker_on_definition
        on_type: checker_on_type
        on_statement: checker_on_statement
        on_expression: checker_on_expression
        on_node: checker_on_node

    ast.visit_module(check_visitor, module)
    if not checker.errors.is_empty():
        raise new_errors(checker.errors)

fn checker_on_definition(checker: TypeChecker, definition: ast.Definition, phase: ast.VisitPhase):
    pass

fn checker_on_type(checker: TypeChecker, ty: ast.MyType, phase: ast.VisitPhase):
    pass

fn assign_types(variables: List[ast.Variable], typs: List[ast.MyType]):
    # TODO: this double for loops requires its own scope .. (only in python backend)
    let pi = typs.iter()
    for v in variables:
        let ty = option_unwrap(pi.next())
        v.ty = ty

fn checker_on_statement(checker: TypeChecker, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Mid:
            case statement.kind:
                Case(case_statement):
                    if ast.is_enum_type(case_statement.value.ty):
                        for arm in case_statement.arms:
                            case ast.get_enum_variant(case_statement.value.ty, arm.name):
                                Some(variant):
                                    let payload_types = ast.get_variant_payload_types(case_statement.value.ty, variant)
                                    if payload_types.len() == arm.variables.len():
                                        assign_types(arm.variables, payload_types)
                                    else:
                                        checker.add_error(arm.location, "Got {arm.variables.len()}, expected {payload_types.len()} values")
                                    # expression.kind = ast.ExpressionKind.Variant(ty3, variant)
                                None:
                                    checker.add_error(arm.location, "No such enum variant: {arm.name}")
                    else:
                        checker.add_error(case_statement.value.location, "Got {ast.type_to_string(case_statement.value.ty)}, expected enum")
                For(for_statement):
                    if ast.has_field(for_statement.iter_value.ty, "iter"):
                        # TODO: we have a few assumptions here, which panic. Should be proper warning:
                        # print("FORRRRRR")
                        let iter_ty: ast.MyType = ast.get_return_type(option_unwrap(ast.get_field_type(for_statement.iter_value.ty, "iter")))
                        # print("iter ty: {ast.type_to_string(iter_ty)}")
                        let opt_ty: ast.MyType = ast.get_return_type(option_unwrap(ast.get_field_type(iter_ty, "next")))
                        # print("Opt ty: {ast.type_to_string(opt_ty)}")
                        let opt_variant = option_unwrap(ast.get_enum_variant(opt_ty, "Some"))
                        let val_ty: ast.MyType = ast.get_variant_payload_types(opt_ty, opt_variant).first()
                        # print("Val ty: {ast.type_to_string(val_ty)}")
                        for_statement.iter_var.ty = val_ty
                    else:
                        checker.add_error(for_statement.iter_value.location, "Value cannot be iterated: {ast.type_to_string(for_statement.iter_value.ty)}")
            else:
                pass
        Post:
            case statement.kind:
                Let(let_statement):
                    case let_statement.type_hint:
                        Some(ty):
                            checker.coerce(ty, let_statement.value)
                            let_statement.variable.ty = ty
                        None:
                            let_statement.variable.ty = let_statement.value.ty
                Pass:
                    pass
                Break:
                    pass
                Continue:
                    pass
                If(if_statement):
                    checker.coerce(ast.bool_type(), if_statement.condition)
                While(while_statement):
                    checker.coerce(ast.bool_type(), while_statement.condition)
                Loop(loop_statement):
                    pass
                Assignment(target, op, value):
                    checker.coerce(target.ty, value)
            else:
                pass
    else:
        pass

fn checker_on_expression(checker: TypeChecker, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                Call(call):
                    case call.callee.ty.kind:
                        Function(parameter_types, return_type):
                            checker.check_arguments(expression.location, parameter_types, call.arguments)
                            expression.ty = ast.deref_type_var(return_type)
                    else:
                        checker.add_error(expression.location, "Cannot call non-function type {ast.type_to_string(call.callee.ty)}")
                LoadSymbol(symbol):
                    case symbol:
                        ExternFunction(f):
                            expression.ty = ast.extern_function_type(f)
                        Function(f):
                            expression.ty = ast.get_function_type(f)
                        Parameter(p):
                            # TODO: clone type?
                            expression.ty = p.ty
                        Var(v):
                            # TODO: clone type?
                            expression.ty = v.ty
                    else:
                        panic("Must not happen: {ast.symbol_to_str(symbol)}")
                VarRef(v):
                    expression.ty = v.ty
                TypeConstructor(tycon):
                    panic("checker: TODO: tycon")
                Type(t):
                    panic("TODO: type")
                Binop(b):
                    # panic("TODO: binop")
                    let ty = b.lhs.ty
                    checker.coerce(ty, b.lhs)
                    checker.coerce(ty, b.rhs)
                    if ast.is_comparison_op(b.op):
                        expression.ty = ast.bool_type()
                    else:
                        expression.ty = ty
                Unop(op, rhs):
                    let ty = rhs.ty
                    # panic("TODO: unop")
                    # TODO: some checking might be nice
                    expression.ty = ty
                NameRef(name):
                    panic("names must be resolved")
                Variant(ty, v):
                    panic("variants must be literals")
                Undefined:
                    panic("TODO: undefined")
                ObjInit(ty, fields):
                    panic("obj init must be rewritten")
                GetAttr(base, attr):
                    # panic("TODO: get attr")
                    case ast.get_field_type(base.ty, attr):
                        Some(ty):
                            expression.ty = ty
                        None:
                            checker.add_error(expression.location, "Type {ast.type_to_string(base.ty)} has no field: {attr}")
                GetIndex(base,indici):
                    panic("TODO: get index")
                EnumLiteral(ty, variant, values):
                    let payload_types = ast.get_variant_payload_types(ty, variant)
                    checker.check_arguments(expression.location, payload_types, values)
                    expression.ty = ty
                ClassLiteral(ty):
                    # panic("TODO: class literal")
                    expression.ty = ty
                StructLiteral(ty, values):
                    let field_types = ast.get_field_types(ty)
                    checker.check_arguments(expression.location, field_types, values)
                    expression.ty = ty
                StringLiteral(s):
                    expression.ty = ast.str_type()
                BoolLiteral(b):
                    expression.ty = ast.bool_type()
                IntLiteral(i):
                    expression.ty = ast.int_type()
                FloatLiteral(b):
                    expression.ty = ast.float_type()
    else:
        pass


fn checker_on_node(checker: TypeChecker, node: ast.VisitNode, phase: ast.VisitPhase):
    pass

class TypeChecker:
    var errors: List[CompilationError] = List()

    fn check_arguments(location: Location, parameter_types: List[ast.MyType], arguments: List[ast.Expression]):
        if parameter_types.len() == arguments.len():
            let p_iter = parameter_types.iter()
            for argument in arguments:
                let p_ty = option_unwrap(p_iter.next())
                this.coerce(p_ty, argument)
        else:
            this.add_error(location, "got {arguments.len()} arguments, expected {parameter_types.len()}")

    fn coerce(ty: ast.MyType, value: ast.Expression):
        if this.unify(value.ty, ty):
            pass
        else:
            this.add_error(value.location, "Got {ast.type_to_string(value.ty)}, expected {ast.type_to_string(ty)}")
    
    fn unify(ty1: ast.MyType, ty2: ast.MyType) -> bool:
        if ast.is_int_type(ty1) and ast.is_int_type(ty2):
            return true
        elif ast.is_void_type(ty1) and ast.is_void_type(ty2):
            return true
        elif ast.is_str_type(ty1) and ast.is_str_type(ty2):
            return true
        elif ast.is_bool_type(ty1) and ast.is_bool_type(ty2):
            return true
        elif ast.is_float_type(ty1) and ast.is_float_type(ty2):
            return true
        elif ast.is_tycon_app_type(ty1) and ast.is_tycon_app_type(ty2):
            let tycon1 = ast.get_tycon(ty1)
            let tycon2 = ast.get_tycon(ty2)
            if ast.tycon_equal(tycon1, tycon2):
                let type_arguments1 = ast.get_type_arguments(ty1)
                let type_arguments2 = ast.get_type_arguments(ty2)
                return this.unify_many(type_arguments1, type_arguments2)
            else:
                return false
        elif ast.is_type_parameter_type(ty1) and ast.is_type_parameter_type(ty2):
            let tp1 = ast.get_type_parameter_from_type(ty1)
            let tp2 = ast.get_type_parameter_from_type(ty2)
            return ast.node_id_equal(tp1.node_id, tp2.node_id)
        elif ast.is_function_type(ty1) and ast.is_function_type(ty2):
            let ptys1 = ast.get_parameter_types_from_type(ty1)
            let ptys2 = ast.get_parameter_types_from_type(ty2)

            if not this.unify_many(ptys1, ptys2):
                return false
            
            let rty1 = ast.get_return_type_from_type(ty1)
            let rty2 = ast.get_return_type_from_type(ty2)
            if not this.unify(rty1, rty2):
                return false

            return true
        elif ast.is_type_var_type(ty1):
            let type_var1: ast.TypeVariable = ast.get_type_var_from_type(ty1)
            case type_var1.ty:
                None:
                    if ast.is_type_var_type(ty2):
                        let type_var2: ast.TypeVariable = ast.get_type_var_from_type(ty2)
                        return ast.type_var_equals(type_var1, type_var2)
                    else:
                        type_var1.ty = Option.Some(ty2)
                        ast.change_type_to(ty1, ty2)
                        return true
                Some(assigned_ty):
                    ast.change_type_to(ty1, assigned_ty)
                    return this.unify(ty1, ty2)
        elif ast.is_type_var_type(ty2):
            return this.unify(ty2, ty1)
        else:
            return false
    
    fn unify_many(typs1: List[ast.MyType], typs2: List[ast.MyType]) -> bool:
        if typs1.len() == typs2.len():
            let typs2_it = typs2.iter()
            for ty1 in typs1:
                let ty2 = option_unwrap(typs2_it.next())
                if not this.unify(ty1, ty2):
                    return false
            return true
        else:
            return false

    fn add_error(location: Location, message: str):
        let err = new_error(location, message)
        # display_error(err)
        this.errors.append(err)
