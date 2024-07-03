# generate bytecode

import ast
from std import print
from datatypes import List, option_unwrap, Option, option_is_some, option_is_none
from dicttype import Dictionary
from vectype import Vector, new_vector
from utils import panic, log_info, log_debug, assert, log_trace
from bc import Instruction
import bc


fn gen_bytecode(module_set: ast.ModuleSet) -> bc.Program:
    let g = BytecodeGenerator()
    g.forward_declarations(module_set)
    for module in module_set.modules:
        g.gen_prog(module)
    return bc.Program(functions: g.functions, structs: g.structs, globals: g.global_variables, extern_functions: g.extern_functions)

struct Loop:
    continue_label: int
    break_label: int

class BytecodeGenerator:
    var id_counter: int = 1
    var is_reachable: bool = true
    var code: Vector[Instruction] = new_vector(default: Instruction.Nop())

    var global_variables: List[bc.Global] = List()
    var global_var_mapping: Dictionary[int] = Dictionary()
    var local_variables: List[bc.Type] = List()
    var local_var_mapping: Dictionary[int] = Dictionary()
    var label_mapping: Dictionary[int] = Dictionary()
    var struct_mapping: Dictionary[int] = Dictionary()
    var extern_functions: List[bc.ExternFunction] = List()

    var structs: List[bc.Struct] = List()
    var functions: List[bc.Function] = List()
    var function_map: Dictionary[int] = Dictionary()
    var loop_stack: List[Loop] = List()

    fn forward_declarations(module_set: ast.ModuleSet):
        let index = 0
        let func_index = 0
        for module in module_set.modules:
            for definition1 in module.definitions:
                case definition1:
                    Struct(struct_def):
                        struct_mapping.insert(key: ast.node_id_to_string(struct_def.id), value: index)
                        index += 1
                    Function(function_def):
                        if option_is_some(function_def.body):
                            function_map.insert(key: function_def.name, value: func_index)
                            func_index += 1
                else:
                    pass

        for module in module_set.modules:
            for definition2 in module.definitions:
                case definition2:
                    Struct(struct_def):
                        let fields2: List[bc.Type] = List()
                        for field1 in struct_def.fields:
                            fields2.append(get_bc_type(field1.ty))
                        structs.append(bc.Struct(fields: fields2, is_union: struct_def.is_union))
                    Var(variable_def):
                        gen_global_variable(variable_def)
                    Function(function_def):
                        if option_is_none(function_def.body):
                            gen_extern_function(function_def)
                else:
                    pass

    fn gen_prog(module: ast.Module):
        log_info("Generating bytecode for {module.name}")
        for definition in module.definitions:
            case definition:
                Function(function_def):
                    if option_is_some(function_def.body):
                        gen_func(function_def)
                Enum(enum_def):
                    panic("Enum not supported, please rewrite")
                Class(class_def):
                    panic("Classes are not supported, please rewrite into structs with functions.")
            else:
                pass
    
    fn gen_global_variable(variable_def: ast.VariableDef):
        let global_index = global_variables.len()
        let key = ast.node_id_to_string(variable_def.variable.id)
        let name = get_name(variable_def.variable.id)
        begin_code()
        gen_expression(option_unwrap(variable_def.value))
        let value = get_relocated_instructions()
        let global_variable = bc.Global(name, ty: get_bc_type(variable_def.variable.ty), value)
        global_variables.append(global_variable)
        global_var_mapping.insert(key, value: global_index)

    fn gen_extern_function(function_def: ast.FunctionDef):
        let func_index = extern_functions.len()
        let name = function_def.name

        let parameters: List[bc.Type] = List()
        for parameter in function_def.parameters:
            parameters.append(get_bc_type(parameter.ty))

        let return_type = Option.None()
        if not ast.is_void_type(function_def.info.return_type):
            return_type = Option.Some(get_bc_type(function_def.info.return_type))
        let no_return = function_def.info.no_return

        let extern_function = bc.ExternFunction(name, parameters, return_type, no_return)
        extern_functions.append(extern_function)
        function_map.insert(key: name, value: func_index)

    fn gen_func(function_def: ast.FunctionDef):
        log_debug("generate bytecode for {function_def.name}")
        local_var_mapping.clear()
        let parameters: List[bc.Type] = List()
        for parameter in function_def.parameters:
            let p2 = get_bc_type(parameter.ty)
            let parameter_index = parameters.len()
            local_var_mapping.insert(key: ast.node_id_to_string(parameter.id), value: parameter_index)
            parameters.append(p2)
        let return_type = Option.None()
        if not ast.is_void_type(function_def.info.return_type):
            return_type = Option.Some(get_bc_type(function_def.info.return_type))
        begin_code()
        local_variables = List()

        let body = option_unwrap(function_def.body).body
        gen_statement(body)

        # Emit return to void function, or unreachable
        if body.is_terminator:
            is_reachable = true
            emit(Instruction.Unreachable())
        else:
            if is_reachable:
                emit(Instruction.Return(n_arg: 0))

        let instructions = get_relocated_instructions()
        let locals = local_variables
        let name = function_def.name
        let no_return = function_def.info.no_return
        functions.append(bc.Function(name, parameters, return_type, no_return, locals, instructions))

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            Pass:
                pass
            Break:
                let inner_most_loop = loop_stack.last()
                jump(target: inner_most_loop.break_label)
            Continue:
                let inner_most_loop = loop_stack.last()
                jump(target: inner_most_loop.continue_label)
            Expr(expr):
                gen_expression(expr)
                assert(condition: ast.is_void_type(expr.ty), message: "Expression must be void!")
            Assignment(target, op, value):
                gen_assignment(target, op, value)
            While(while_statement):
                gen_while_statement(while_statement)
            If(if_statement):
                gen_if_statement(if_statement)
            Loop(loop_statement):
                panic("Loop not implemented")
            For(for_statement):
                panic("For-statement not supported")
            Try(try_statement):
                gen_try_statement(try_statement)
            Case(case_statement):
                panic("Case-statement not supported")
            Let(let_statement):
                gen_expression(let_statement.value)
                let var_index = add_local(variable: let_statement.variable)
                emit(Instruction.LocalSet(var_index))
            Compound(inner):
                for s in inner:
                    gen_statement(s)
            Switch(switch_statement):
                panic("Switch not implemented")
            Unreachable:
                emit(Instruction.Unreachable())
            Return(opt_val):
                case opt_val:
                    Some(val):
                        gen_expression(val)
                        emit(Instruction.Return(n_arg: 1))
                    None:
                        emit(Instruction.Return(n_args: 0))
                is_reachable = false
            Raise(val):
                gen_expression(val)
                emit(Instruction.Raise())
                is_reachable = false
    
    fn gen_assignment(target: ast.Expression, op: Option[ast.BinaryOperator], value: ast.Expression):
        case target.kind:
            GetAttr(base, attr):
                gen_expression(base)
                let index = get_attr_index(ty: base.ty, attr)
                case op:
                    Some(op):
                        emit(Instruction.Dup())
                        emit(Instruction.GetAttr(index, ty: get_bc_type(target.ty)))
                        gen_expression(value)
                        gen_binop(op)
                    None:
                        gen_expression(value)
                emit(Instruction.SetAttr(index))
            GetIndex(base, indici):
                gen_expression(base)
                assert(condition: indici.len() == 1, message: "Unsupported: multi-indexing")
                let index = indici.first()
                gen_expression(index)
                case op:
                    Some(op):
                        emit(Instruction.GetIndex())
                        gen_expression(value)
                        gen_binop(op)
                        # TBD: we do want to duplicate base and index here
                        panic("x[y] += not implemented")
                    None:
                        gen_expression(value)
                emit(Instruction.SetIndex())
            VarRef(variable):
                if is_local_variable(variable):
                    let index = get_local_index(variable)
                    case op:
                        Some(op):
                            emit(Instruction.LocalGet(index))
                            gen_expression(value)
                            gen_binop(op)
                        None:
                            gen_expression(value)
                    emit(Instruction.LocalSet(index))
                else:
                    let index = get_global_index(variable)
                    case op:
                        Some(op):
                            emit(Instruction.GlobalGet(index))
                            gen_expression(value)
                            gen_binop(op)
                        None:
                            gen_expression(value)
                    emit(Instruction.GlobalSet(index))
            ParameterRef(parameter_def):
                let parameter_index = get_parameter_index(parameter_def)
                case op:
                    Some(op):
                        emit(Instruction.ParameterGet(parameter_index))
                        gen_expression(value)
                        gen_binop(op)
                    None:
                        gen_expression(value)
                emit(Instruction.ParameterSet(parameter_index))

        else:
            panic("Cannot assign: {ast.expression_to_string(target)}")
    
    fn gen_try_statement(try_statement: ast.TryStatement):
        log_trace("gen_try_statement")
        let try_label = new_label()
        let except_label = new_label()
        let final_label = new_label()

        let except_var_index = add_local(variable: try_statement.except_var)
        emit(Instruction.SetupTry(try_label, except_label))

        set_label(try_label)
        gen_statement(try_statement.try_block.body)
        emit(Instruction.PopTry())
        jump(final_label)

        set_label(except_label)
        emit(Instruction.PopTry())
        emit(Instruction.GetExceptionValue())
        emit(Instruction.LocalSet(index: except_var_index))
        gen_statement(try_statement.except_block.body)
        jump(final_label)

        set_label(final_label)

    fn gen_while_statement(while_statement: ast.WhileStatement):
        log_trace("gen_while_statement")
        let test_label = new_label()
        let body_label = new_label()
        let final_label = new_label()
        loop_stack.append(Loop(continue_label: test_label, break_label: final_label))

        set_label(test_label)
        gen_condition(condition: while_statement.condition, true_label: body_label, false_label: final_label)

        set_label(body_label)
        gen_statement(while_statement.block.body)
        jump(test_label)

        loop_stack.drop_last()
        set_label(final_label)

    fn gen_if_statement(if_statement: ast.IfStatement):
        let true_label = new_label()
        let false_label = new_label()
        let final_label = new_label()

        gen_condition(condition: if_statement.condition, true_label, false_label)
        
        set_label(true_label)
        gen_statement(if_statement.true_block.body)
        jump(final_label)

        set_label(false_label)
        gen_statement(if_statement.false_block.body)
        jump(final_label)

        set_label(final_label)

    fn gen_condition(condition: ast.Expression, true_label: int, false_label: int):
        # Generate short circuit logic for 'and' and 'or' conditions
        # Otherwise, evaluate the condition, and use jump-if
        case condition.kind:
            Binop(binop):
                case binop.op:
                    And:
                        # Both sides must be true
                        # If the first condition is true, we must check the second one.
                        let middle_label = new_label()
                        gen_condition(condition: binop.lhs, true_label: middle_label, false_label)
                        set_label(middle_label)
                        gen_condition(condition: binop.rhs, true_label, false_label)
                    Or:
                        # One condition must be true must be true
                        # If the first condition is true, we are done. Otherwise, check the second condition
                        let middle_label = new_label()
                        gen_condition(condition: binop.lhs, true_label, false_label: middle_label)
                        set_label(middle_label)
                        gen_condition(condition: binop.rhs, true_label, false_label)
                else:
                    gen_expression(condition)
                    jump_if(label: true_label, label2: false_label)
            Unop(op, rhs):
                case op:
                    Not:
                        gen_condition(condition: rhs, true_label: false_label, false_label: true_label)
                else:
                    gen_expression(condition)
                    jump_if(label: true_label, label2: false_label)
        else:
            gen_expression(condition)
            jump_if(label: true_label, label2: false_label)

    fn condition_as_value(condition: ast.Expression):
        # Evaluate a condition into a value on the stack.

        # Create a local variable for the result:
        let ty = bc.Type.Int()
        let index = new_local(ty)

        # Evaluate the condition, and branch:
        let true_label = new_label()
        let false_label = new_label()
        let final_label = new_label()
        gen_condition(condition, true_label, false_label)

        set_label(true_label)
        emit(Instruction.Literal(bc.LiteralValue.Bool(value: true)))
        emit(Instruction.LocalSet(index))
        jump(final_label)

        set_label(false_label)
        emit(Instruction.Literal(bc.LiteralValue.Bool(value: false)))
        emit(Instruction.LocalSet(index))
        jump(final_label)

        set_label(final_label)
        emit(Instruction.LocalGet(index))

    fn gen_expression(expression?: ast.Expression):
        case expression.kind:
            Call(call):
                gen_call(call)
            GetAttr(base, attr):
                gen_expression(base)
                let index = get_attr_index(ty: base.ty, attr)
                emit(Instruction.GetAttr(index, ty: get_bc_type(expression.ty)))
            GetIndex(base, indici):
                gen_expression(base)
                assert(condition: indici.len() == 1, message: "Unsupported: multi-indexing")
                let index = indici.first()
                gen_expression(index)
                emit(Instruction.GetIndex())
            Binop(binop):
                case binop.op:
                    And:
                        condition_as_value(condition: expression)
                    Or:
                        condition_as_value(condition: expression)
                else:
                    gen_binop_expr(binop)
            Unop(op, value):
                gen_expression(value)
                case op:
                    Not:
                        emit(Instruction.Not())
                    Minus:
                        emit(Instruction.Neg())
            IntLiteral(value):
                emit(Instruction.Literal(bc.LiteralValue.Int(value)))
            FloatLiteral(value):
                emit(Instruction.Literal(bc.LiteralValue.Float(value)))
            StringLiteral(value):
                emit(Instruction.Literal(bc.LiteralValue.Str(value)))
            CharLiteral(value):
                emit(Instruction.Literal(bc.LiteralValue.Char(value)))
            BoolLiteral(value):
                emit(Instruction.Literal(bc.LiteralValue.Bool(value)))
            VarRef(variable):
                if is_local_variable(variable):
                    let var_index = get_local_index(variable)
                    emit(Instruction.LocalGet(var_index))
                else:
                    let var_index = get_global_index(variable)
                    emit(Instruction.GlobalGet(var_index))
            FunctionRef(function_def, type_arguments):
                if option_is_some(function_def.body):
                    let funcidx = function_map.get(key: function_def.name)
                    emit(Instruction.LoadFunc(funcidx))
                else:
                    panic("Extern function pointer to {function_def.name} not supported")
            ParameterRef(parameter_def):
                let parameter_index = get_parameter_index(parameter_def)
                emit(Instruction.ParameterGet(parameter_index))
            StructLiteral(ty, values):
                for value in values:
                    gen_expression(value)
                let struct_def = ast.get_struct_def_from_type(ty)
                let struct_index = struct_mapping.get(key: ast.node_id_to_string(struct_def.id))
                emit(Instruction.StructLiteral(struct_index))
            UnionLiteral(ty, field, value):
                gen_expression(value)
                let struct_def = ast.get_struct_def_from_type(ty)
                let struct_index = struct_mapping.get(key: ast.node_id_to_string(struct_def.id))
                let field_index = get_attr_index(ty, attr: field)
                emit(Instruction.UnionLiteral(struct_index, field_index))
            ArrayLiteral(values):
                for value in values:
                    gen_expression(value)
                emit(Instruction.ArrayLiteral(n_values: values.len()))
            ArrayLiteral2(value, size):
                gen_expression(value)
                gen_expression(size)
                emit(Instruction.ArrayLiteral2())
            TypeCast(ty, value):
                gen_expression(value)
                if ast.is_float_type(ty):
                    if ast.is_int_type(value.ty):
                        emit(Instruction.IntToFloat())
                    elif ast.is_opaque_type(value.ty):
                        emit(Instruction.FromOpaque(get_bc_type(ty)))
                    else:
                        panic("cannot cast to float: {ast.type_to_string(value.ty)}")
                elif ast.is_int_type(ty):
                    if ast.is_float_type(value.ty):
                        emit(Instruction.FloatToInt())
                    elif ast.is_opaque_type(value.ty):
                        emit(Instruction.FromOpaque(get_bc_type(ty)))
                    else:
                        panic("cannot cast to float: {ast.type_to_string(value.ty)}")
                elif ast.is_opaque_type(ty):
                    if ast.is_opaque_type(value.ty):
                        pass
                    else:
                        emit(Instruction.ToOpaque(get_bc_type(value.ty)))
                elif ast.is_opaque_type(value.ty):
                    emit(Instruction.FromOpaque(get_bc_type(ty)))
                else:
                    panic("unsupported type-casting from {ast.type_to_string(value.ty)} to {ast.type_to_string(ty)}")
        else:
            panic("Unsupported: {ast.expression_to_string(expression)}")

    fn gen_call(call: ast.FunctionCall):
        for argument in call.arguments:
            gen_expression(argument.value)

        case call.callee.kind:
            FunctionRef(function_def, type_args):
                if option_is_some(function_def.body):
                    # print("call {function_def.id.name}")
                    let key = function_def.name
                    let funcidx = function_map.get(key)
                    emit(Instruction.Call(funcidx))
                else:
                    let key = function_def.name
                    log_debug("Calling extern function: {key}")
                    let funcidx = function_map.get(key)
                    emit(Instruction.CallExtern(funcidx))

                if function_def.info.no_return:
                    is_reachable = false
        else:
            gen_indirect_call(callee: call.callee)

    fn gen_indirect_call(callee: ast.Expression):
        gen_expression(callee)
        let parameter_types: List[bc.Type] = List()
        for p2 in ast.get_parameter_types_from_type(callee.ty):
            parameter_types.append(get_bc_type(p2.ty))
        let return_type: Option[bc.Type] = Option.None()
        let return_type2 = ast.get_return_type_from_type(callee.ty)
        if ast.is_void_type(return_type2):
            return_type = Option.None()
        else:
            return_type = Option.Some(get_bc_type(return_type2))
        emit(Instruction.CallIndirect(parameter_types, return_type))

    fn gen_binop_expr(binop: ast.BinopExpression):
        gen_expression(binop.lhs)
        gen_expression(binop.rhs)
        gen_binop(op: binop.op)
    
    fn gen_binop(op: ast.BinaryOperator):
        case op:
            Add:
                emit(Instruction.Binop(op: bc.BinaryOperator.Add()))
            Sub:
                emit(Instruction.Binop(op: bc.BinaryOperator.Sub()))
            Mul:
                emit(Instruction.Binop(op: bc.BinaryOperator.Multiply()))
            Div:
                emit(Instruction.Binop(op: bc.BinaryOperator.Divide()))
            NotEquals:
                emit(Instruction.Comparison(op: bc.ComparisonOperator.NotEquals()))
            Equals:
                emit(Instruction.Comparison(op: bc.ComparisonOperator.Equals()))
            Greater:
                emit(Instruction.Comparison(op: bc.ComparisonOperator.Greater()))
            GreaterEquals:
                emit(Instruction.Comparison(op: bc.ComparisonOperator.GreaterEquals()))
            Less:
                emit(Instruction.Comparison(op: bc.ComparisonOperator.Less()))
            LessEquals:
                emit(Instruction.Comparison(op: bc.ComparisonOperator.LessEquals()))
            And:
                panic("unreachable: and")
            Or:
                panic("unreachable: or")
            BitAnd:
                emit(Instruction.Bitop(op: bc.BitOperator.And()))
            BitXor:
                emit(Instruction.Bitop(op: bc.BitOperator.Xor()))
            BitOr:
                emit(Instruction.Bitop(op: bc.BitOperator.Or()))
            ShiftLeft:
                emit(Instruction.Bitop(op: bc.BitOperator.Shl()))
            ShiftRight:
                emit(Instruction.Bitop(op: bc.BitOperator.Shr()))

    fn new_label() -> int:
        return gen_id()

    fn set_label(label?: int):
        let index = code.len()
        label_mapping.insert(key: "{label}", value: index)
        is_reachable = true
    
    fn translate_label(label?: int) -> int:
        return label_mapping.get(key: "{label}")

    fn begin_code():
        label_mapping = Dictionary()
        code = new_vector(default: Instruction.Nop())
        is_reachable = true

    fn get_relocated_instructions() -> Vector[Instruction]:
        # Apply relocations to labels
        let instructions: Vector[Instruction] = new_vector(default: Instruction.Nop())
        for instruction in code:
            case instruction:
                Jump(label):
                    label = translate_label(label)
                    instructions.append(Instruction.Jump(label))
                JumpIf(label1, label2):
                    label1 = translate_label(label1)
                    label2 = translate_label(label2)
                    instructions.append(Instruction.JumpIf(label1, label2))
                SetupTry(try_label, except_label):
                    try_label = translate_label(try_label)
                    except_label = translate_label(except_label)
                    instructions.append(Instruction.SetupTry(try_label, except_label))
            else:
                instructions.append(instruction)
        return instructions

    fn jump(label?: int):
        emit(Instruction.Jump(target: label))
        is_reachable = false

    fn jump_if(label: int, label2: int):
        emit(Instruction.JumpIf(label1: label, label2))
        is_reachable = false

    fn add_local(variable: ast.Variable) -> int:
        # Add a local variable!
        let ty = get_bc_type(variable.ty)
        let index = new_local(ty)
        local_var_mapping.insert(key: ast.node_id_to_string(variable.id), value: index)
        return index
    
    fn new_local(ty: bc.Type) -> int:
        let index = local_variables.len()
        local_variables.append(ty)
        return index
    
    fn is_local_variable(variable: ast.Variable) -> bool:
        return local_var_mapping.contains(key: ast.node_id_to_string(variable.id))

    fn get_local_index(variable: ast.Variable) -> int:
        let key = ast.node_id_to_string(variable.id)
        return local_var_mapping.get(key)

    fn get_global_index(variable: ast.Variable) -> int:
        let key = ast.node_id_to_string(variable.id)
        return global_var_mapping.get(key)

    fn get_parameter_index(parameter_def: ast.ParameterDef) -> int:
        return local_var_mapping.get(key: ast.node_id_to_string(parameter_def.id))

    fn get_bc_type(ty2?: ast.Type) -> bc.Type:
        # Determine the bytecode type for the given ast type
        let ty = bc.Type.Ptr()
        if ast.is_int_type(ty2):
            ty = bc.Type.Int()
        elif ast.is_float_type(ty2):
            ty = bc.Type.Float()
        elif ast.is_str_type(ty2):
            ty = bc.Type.Str()
        elif ast.is_struct_type(ty2):
            let struct_def = ast.get_struct_def_from_type(ty2)
            let index = struct_mapping.get(key: ast.node_id_to_string(struct_def.id))
            ty = bc.Type.StructRef(index)
        elif ast.is_function_type(ty2):
            let parameter_types2 = ast.get_parameter_types_from_type(ty2)
            let return_type2 = ast.get_return_type_from_type(ty2)
            let parameter_types: List[bc.Type] = List()
            for p2 in parameter_types2:
                parameter_types.append(get_bc_type(p2.ty))
            let return_type: Option[bc.Type] = Option.None()
            if ast.is_void_type(return_type2):
                return_type = Option.None()
            else:
                return_type = Option.Some(get_bc_type(return_type2))
            ty = bc.Type.Function(parameter_types, return_type)
        elif ast.is_type_parameter_type(ty2):
            ty = bc.Type.Ptr()
        elif ast.is_bool_type(ty2):
            ty = bc.Type.Int()
        elif ast.is_char_type(ty2):
            ty = bc.Type.Char()
        elif ast.is_opaque_type(ty2):
            ty = bc.Type.Ptr()
        elif ast.is_array_type(ty2):
            let element_type2 = ast.get_element_type_from_type(ty2)
            ty = bc.Type.Array(get_bc_type(element_type2))
        else:
            panic("Type: {ast.type_to_string(ty2)} not supported")
        return ty

    fn emit(instruction?: Instruction):
        # print("Inst: {bc.instruction_to_string(instruction)}")
        if is_reachable:
            code.append(instruction)

    fn get_name(id?: ast.NodeId) -> str:
        return "X{id.id}_{id.name}"

    fn gen_id() -> int:
        let x = id_counter
        id_counter += 1
        return x


fn get_attr_index(ty: ast.Type, attr: str) -> int:
    let struct_def = ast.get_struct_def_from_type(ty)
    let index = 0
    for field in struct_def.fields:
        if field.name == attr:
            return index
        index += 1
    panic("No field: {attr}")
