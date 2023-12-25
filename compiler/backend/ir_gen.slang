# generate bytecode

import ast
from std import print
from datatypes import List, Dictionary, option_unwrap, Option, option_is_some
from utils import panic, log_info, log_debug, assert
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
    var code: List[Instruction] = List()

    var global_variables: List[bc.Type] = List()
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
        for module in module_set.modules:
            let index = 0
            let func_index = 0
            for definition1 in module.definitions:
                case definition1:
                    Struct(struct_def):
                        struct_mapping.insert(key: ast.node_id_to_string(struct_def.id), value: index)
                        index += 1
                    Function(function_def):
                        function_map.insert(key: ast.node_id_to_string(function_def.id), value: func_index)
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
                        let global_index = global_variables.len()
                        let global_variable = get_bc_type(variable_def.variable.ty)
                        global_variables.append(global_variable)
                        global_var_mapping.insert(key: ast.node_id_to_string(variable_def.variable.id), value: global_index)
                    ExternFunction(extern_function_def):
                        let func_index = extern_functions.len()
                        let name = extern_function_def.name

                        let parameters: List[bc.Type] = List()
                        for parameter in extern_function_def.parameter_types:
                            parameters.append(get_bc_type(parameter))

                        let return_type = Option.None()
                        if not ast.is_void_type(extern_function_def.return_type):
                            return_type = Option.Some(get_bc_type(extern_function_def.return_type))

                        let extern_function = bc.ExternFunction(name, parameters, return_type)
                        extern_functions.append(extern_function)
                        function_map.insert(key: name, value: func_index)
                else:
                    pass

    fn gen_prog(module: ast.Module):
        log_info("Generating bytecode for {module.name}")
        for definition in module.definitions:
            case definition:
                Function(function_def):
                    gen_func(function_def)
                Enum(enum_def):
                    panic("Enum not supported, please rewrite")
                Class(class_def):
                    panic("Classes are not supported, please rewrite into structs with functions.")
            else:
                pass

    fn gen_func(function_def: ast.FunctionDef):
        log_debug("generate bytecode for {function_def.id.name}")
        let parameters: List[bc.Type] = List()
        for parameter in function_def.parameters:
            let p2 = get_bc_type(parameter.ty)
            let parameter_index = parameters.len()
            local_var_mapping.insert(key: ast.node_id_to_string(parameter.id), value: parameter_index)
            parameters.append(p2)
        let return_type = Option.None()
        if not ast.is_void_type(function_def.return_type):
            return_type = Option.Some(get_bc_type(function_def.return_type))
        label_mapping = Dictionary()
        code = List()
        local_variables = List()
        is_reachable = true

        gen_statement(function_def.body)

        if is_reachable:
            # Emit return to void function
            emit(Instruction.Return(n_arg: 0))

        let instructions = get_relocated_instructions()
        let locals = local_variables
        functions.append(bc.Function(name: function_def.id.name, parameters, return_type, locals, instructions))

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
                panic("For-statement not supported")
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
                panic("Raise not implemented")
    
    fn gen_assignment(target: ast.Expression, op: Option[ast.BinaryOperator], value: ast.Expression):
        case target.kind:
            GetAttr(base, attr):
                gen_expression(base)
                let index = get_attr_index(ty: base.ty, attr)
                case op:
                    Some(op):
                        emit(Instruction.GetAttr(index, ty: get_bc_type(target.ty)))
                        gen_expression(value)
                        gen_binop(op)
                    None:
                        gen_expression(value)
                emit(Instruction.SetAttr(index))
            GetIndex(base, indici):
                gen_expression(base)
                gen_expression(value)
                # TODO: handle optional operator, like += and -=
                panic("TODO assign x[y] =")
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
            LoadSymbol(symbol):
                case symbol:
                    Parameter(parameter_def):
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
                    panic("Cannot assign symbol: {ast.symbol_to_str(symbol)}")

        else:
            panic("Cannot assign: {ast.expression_to_string(target)}")

    fn gen_while_statement(while_statement: ast.WhileStatement):
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
            # TODO: unop -> not 
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
                # TODO: optionally cast from void to type (type erasure)
                let index = get_attr_index(ty: base.ty, attr)
                emit(Instruction.GetAttr(index, ty: get_bc_type(expression.ty)))
            GetIndex(base, indici):
                gen_expression(base)
                panic("TODO: get-index")
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
                emit(Instruction.LoadFunc(name: function_def.id.name))
            LoadSymbol(symbol):
                case symbol:
                    ExternFunction(e):
                        emit(Instruction.LoadFunc(name: e.name))
                    Parameter(parameter_def):
                        let parameter_index = get_parameter_index(parameter_def)
                        emit(Instruction.ParameterGet(parameter_index))
                else:
                    panic("Cannot load symbol {ast.symbol_to_str(symbol)}")
            StructLiteral(ty, values):
                for value in values:
                    gen_expression(value)
                let struct_def = ast.get_struct_def_from_type(ty)
                let struct_index = option_unwrap(struct_mapping.get(key: ast.node_id_to_string(struct_def.id)))
                emit(Instruction.StructLiteral(struct_index))
            UnionLiteral(ty, field, value):
                gen_expression(value)
                let struct_def = ast.get_struct_def_from_type(ty)
                let struct_index = option_unwrap(struct_mapping.get(key: ast.node_id_to_string(struct_def.id)))
                let field_index = get_attr_index(ty, attr: field)
                emit(Instruction.UnionLiteral(struct_index, field_index))
            ArrayLiteral(values):
                for value in values:
                    gen_expression(value)
                emit(Instruction.ArrayLiteral(n_values: values.len()))
            ArrayLiteral2(value, size):
                panic("TODO: ArrayLiteral2!")
            TypeCast(ty, value):
                gen_expression(value)
                if ast.is_int_type(value.ty) and ast.is_float_type(ty):
                    emit(Instruction.IntToFloat())
                elif ast.is_opaque_type(value.ty) and ast.is_opaque_type(ty):
                    pass
                elif ast.is_opaque_type(value.ty) and ast.is_struct_type(ty):
                    # TODO: we might require a cast here?
                    pass
                elif ast.is_struct_type(value.ty) and ast.is_opaque_type(ty):
                    # TODO: we might require a cast here?
                    pass
                elif ast.is_opaque_type(ty):
                    # Assume all values can be opaque?
                    # TBD: is this a valid assumption?
                    pass
                elif ast.is_opaque_type(value.ty):
                    # Assume casting from opaque is trouble-less
                    pass
                else:
                    panic("TODO: unsupported type-casting from {ast.type_to_string(value.ty)} to {ast.type_to_string(ty)}")
        else:
            panic("Unsupported: {ast.expression_to_string(expression)}")

    fn gen_call(call: ast.FunctionCall):
        for argument in call.arguments:
            gen_expression(argument.value)

        #let return_type = ast.get_return_type_from_type(call.callee.ty)
        #let result_type: Option[bc.Type] = Option.None()
        #if not ast.is_void_type(return_type):
        #    result_type = Option.Some(get_bc_type(return_type))
        #emit(Instruction.Call(n_args: call.arguments.len(), result_type))

        case call.callee.kind:
            LoadSymbol(symbol):
                case symbol:
                    ExternFunction(external_function_def):
                        let key = external_function_def.name
                        log_debug("Calling extern function: {key}")
                        let funcidx = option_unwrap(function_map.get(key))
                        emit(Instruction.CallExtern(funcidx))
                else:
                    gen_indirect_call(callee: call.callee)

            FunctionRef(function_def, type_args):
                # print("call {function_def.id.name}")
                let key = ast.node_id_to_string(function_def.id)
                let funcidx = option_unwrap(function_map.get(key))
                emit(Instruction.Call(funcidx))
        else:
            gen_indirect_call(callee: call.callee)

    fn gen_indirect_call(callee: ast.Expression):
        panic("TODO: gen_indirect_call")

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
        return option_unwrap(label_mapping.get(key: "{label}"))

    fn get_relocated_instructions() -> List[Instruction]:
        # Apply relocations to labels
        let instructions: List[Instruction] = List()
        for instruction in code:
            case instruction:
                Jump(label):
                    label = translate_label(label)
                    instructions.append(Instruction.Jump(label))
                JumpIf(label1, label2):
                    label1 = translate_label(label1)
                    label2 = translate_label(label2)
                    instructions.append(Instruction.JumpIf(label1, label2))
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
        return option_is_some(local_var_mapping.get(key: ast.node_id_to_string(variable.id)))

    fn get_local_index(variable: ast.Variable) -> int:
        return option_unwrap(local_var_mapping.get(key: ast.node_id_to_string(variable.id)))

    fn get_global_index(variable: ast.Variable) -> int:
        return option_unwrap(global_var_mapping.get(key: ast.node_id_to_string(variable.id)))

    fn get_parameter_index(parameter_def: ast.ParameterDef) -> int:
        return option_unwrap(local_var_mapping.get(key: ast.node_id_to_string(parameter_def.id)))

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
            let index = option_unwrap(struct_mapping.get(key: ast.node_id_to_string(struct_def.id)))
            ty = bc.Type.StructRef(index)
        elif ast.is_function_type(ty2):
            let parameter_types2 = ast.get_parameter_types_from_type(ty2)
            let parameter_types: List[bc.Type] = List()
            for p2 in parameter_types2:
                parameter_types.append(get_bc_type(p2))
            ty = bc.Type.Function(parameter_types)
        elif ast.is_type_parameter_type(ty2):
            ty = bc.Type.Ptr()
        elif ast.is_bool_type(ty2):
            ty = bc.Type.Int()
        elif ast.is_char_type(ty2):
            ty = bc.Type.Char()
        elif ast.is_opaque_type(ty2):
            ty = bc.Type.Ptr()
        else:
            panic("Type: {ast.type_to_string(ty2)} not supported")
        return ty

    fn emit(instruction?: Instruction):
        # print("Inst: {bc.instruction_to_string(instruction)}")
        if is_reachable:
            code.append(instruction)

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
