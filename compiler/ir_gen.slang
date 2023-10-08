# generate bytecode

import ast
from std import print
from datatypes import List, Dictionary, option_unwrap, Option
from utils import panic, log_info, log_debug
from bc import Instruction, instruction_to_string
import bc


fn gen_bytecode(module_set: ast.ModuleSet) -> bc.Program:
    let g = Generator()
    for module in module_set.modules:
        log_info("Generating bytecode for {module.name}")
        g.gen_prog(module)
    return bc.Program(functions: g.functions, structs: g.structs)

struct Loop:
    continue_label: int
    break_label: int

class Generator:
    var id_counter: int = 1
    var is_reachable: bool = true
    var code: List[Instruction] = List()

    var local_variables: List[bc.Type] = List()
    var local_var_mapping: Dictionary[int] = Dictionary()
    var label_mapping: Dictionary[int] = Dictionary()
    var struct_mapping: Dictionary[int] = Dictionary()

    var structs: List[bc.Struct] = List()
    var functions: List[bc.Function] = List()
    var loop_stack: List[Loop] = List()

    fn gen_prog(module: ast.Module):
        let index = 0
        for definition1 in module.definitions:
            case definition1:
                Struct(struct_def):
                    this.struct_mapping.insert(key: ast.node_id_to_string(struct_def.id), value: index)
                    index += 1
            else:
                pass

        for definition2 in module.definitions:
            case definition2:
                Struct(struct_def):
                    let fields2: List[bc.Type] = List()
                    for field1 in struct_def.fields:
                        fields2.append(this.get_bc_type(field1.ty))
                    this.structs.append(bc.Struct(fields: fields2, is_union: struct_def.is_union))
            else:
                pass

        for definition in module.definitions:
            case definition:
                Function(function_def):
                    this.gen_func(function_def)
                ExternFunction(e):
                    pass
                Enum(e):
                    panic("Enum not supported, please rewrite")
                Struct(s):
                    pass
                Class(c):
                    panic("Classes are not supported, please rewrite into structs with functions.")
                Var(v):
                    panic("VAR def not impl.")

    fn gen_func(function_def: ast.FunctionDef):
        log_debug("generate bytecode for {function_def.id.name}")
        let parameters: List[bc.Type] = List()
        for parameter in function_def.parameters:
            let p2 = this.get_bc_type(parameter.ty)
            let parameter_index = parameters.len()
            this.local_var_mapping.insert(key: ast.node_id_to_string(parameter.id), value: parameter_index)
            parameters.append(p2)
        let return_type = Option.None()
        if not ast.is_void_type(function_def.return_type):
            return_type = Option.Some(this.get_bc_type(function_def.return_type))
        this.label_mapping = Dictionary()
        this.code = List()
        this.local_variables = List()
        this.is_reachable = true

        this.gen_statement(function_def.body)

        if this.is_reachable:
            # Emit return to void function
            this.emit(Instruction.Return(n_arg: 0))

        let instructions = this.get_relocated_instructions()
        let locals = this.local_variables
        this.functions.append(bc.Function(name: function_def.id.name, parameters, return_type, locals, instructions))

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            Pass:
                pass
            Break:
                let inner_most_loop = this.loop_stack.last()
                this.jump(target: inner_most_loop.break_label)
            Continue:
                let inner_most_loop = this.loop_stack.last()
                this.jump(target: inner_most_loop.continue_label)
            Expr(expr):
                this.gen_expression(expr)
                if not ast.is_void_type(expr.ty):
                    panic("Expression must be void!")
            Assignment(target, op, value):
                case target.kind:
                    GetAttr(base, attr):
                        this.gen_expression(base)
                        let index = get_attr_index(ty: base.ty, attr)
                        case op:
                            Some(binop):
                                this.emit(Instruction.GetAttr(index, ty: this.get_bc_type(target.ty)))
                                this.gen_expression(value)
                                case binop:
                                    Add:
                                        this.emit(Instruction.Binop(op: bc.BinaryOperator.Add()))
                                    Sub:
                                        this.emit(Instruction.Binop(op: bc.BinaryOperator.Sub()))
                                else:
                                    panic("Can only += and -=")
                            None:
                                this.gen_expression(value)
                        this.emit(Instruction.SetAttr(index))
                    GetIndex(base, indici):
                        this.gen_expression(base)
                        this.gen_expression(value)
                        # TODO: handle optional operator, like += and -=
                        panic("TODO assign x[y] =")
                    VarRef(variable):
                        let index = this.get_local_index(variable)
                        case op:
                            Some(binop):
                                this.emit(Instruction.LocalGet(index))
                                this.gen_expression(value)
                                case binop:
                                    Add:
                                        this.emit(Instruction.Binop(op: bc.BinaryOperator.Add()))
                                    Sub:
                                        this.emit(Instruction.Binop(op: bc.BinaryOperator.Sub()))
                                else:
                                    panic("Can only += and -=")
                            None:
                                this.gen_expression(value)
                        this.emit(Instruction.LocalSet(index))
                else:
                    panic("Cannot assign: {ast.expression_to_string(expression: target)}")
            While(while_statement):
                let test_label = this.new_label()
                let body_label = this.new_label()
                let final_label = this.new_label()
                this.loop_stack.append(Loop(continue_label: test_label, break_label: final_label))

                this.set_label(test_label)
                this.gen_condition(condition: while_statement.condition, true_label: body_label, false_label: final_label)

                this.set_label(body_label)
                this.gen_statement(while_statement.block.body)
                this.jump(test_label)

                this.loop_stack.drop_last()
                this.set_label(final_label)
            If(if_statement):
                let true_label = this.new_label()
                let false_label = this.new_label()
                let final_label = this.new_label()

                this.gen_condition(condition: if_statement.condition, true_label, false_label)
                
                this.set_label(true_label)
                this.gen_statement(if_statement.true_block.body)
                this.jump(final_label)

                this.set_label(false_label)
                this.gen_statement(if_statement.false_block.body)
                this.jump(final_label)

                this.set_label(final_label)
            Loop(loop_statement):
                panic("Loop not implemented")
            For(for_statement):
                panic("For-statement not supported")
            Try(try_statement):
                panic("For-statement not supported")
            Case(case_statement):
                panic("Case-statement not supported")
            Let(let_statement):
                this.gen_expression(let_statement.value)
                let var_index = this.add_local(variable: let_statement.variable)
                this.emit(Instruction.LocalSet(var_index))
            Compound(inner):
                for s in inner:
                    this.gen_statement(s)
            Switch(switch_statement):
                panic("Switch not implemented")
            Return(opt_val):
                case opt_val:
                    Some(val):
                        this.gen_expression(val)
                        this.emit(Instruction.Return(n_arg: 1))
                    None:
                        this.emit(Instruction.Return(n_args: 0))
                this.is_reachable = false
            Raise(val):
                panic("Raise not implemented")
    
    fn gen_condition(condition: ast.Expression, true_label: int, false_label: int):
        # Generate short circuit logic for 'and' and 'or' conditions
        # Otherwise, evaluate the condition, and use jump-if
        case condition.kind:
            Binop(binop):
                case binop.op:
                    And:
                        # Both sides must be true
                        # If the first condition is true, we must check the second one.
                        let middle_label = this.new_label()
                        this.gen_condition(condition: binop.lhs, true_label: middle_label, false_label)
                        this.set_label(middle_label)
                        this.gen_condition(condition: binop.rhs, true_label, false_label)
                    Or:
                        # One condition must be true must be true
                        # If the first condition is true, we are done. Otherwise, check the second condition
                        let middle_label = this.new_label()
                        this.gen_condition(condition: binop.lhs, true_label, false_label: middle_label)
                        this.set_label(middle_label)
                        this.gen_condition(condition: binop.rhs, true_label, false_label)
                else:
                    this.gen_expression(condition)
                    this.jump_if(label: true_label, label2: false_label)
            # TODO: unop -> not 
        else:
            this.gen_expression(condition)
            this.jump_if(label: true_label, label2: false_label)

    fn condition_as_value(condition: ast.Expression):
        # Evaluate a condition into a value on the stack.

        # Create a local variable for the result:
        let ty = bc.Type.Int()
        let index = this.local_variables.len()
        this.local_variables.append(ty)

        # Evaluate the condition, and branch:
        let true_label = this.new_label()
        let false_label = this.new_label()
        let final_label = this.new_label()
        this.gen_condition(condition, true_label, false_label)

        this.set_label(true_label)
        this.emit(Instruction.Literal(bc.LiteralValue.Bool(value: true)))
        this.emit(Instruction.LocalSet(index))
        this.jump(final_label)

        this.set_label(false_label)
        this.emit(Instruction.Literal(bc.LiteralValue.Bool(value: false)))
        this.emit(Instruction.LocalSet(index))
        this.jump(final_label)

        this.set_label(final_label)
        this.emit(Instruction.LocalGet(index))

    fn gen_expression(expression?: ast.Expression):
        case expression.kind:
            Call(call):
                this.gen_expression(call.callee)
                for argument in call.arguments:
                    this.gen_expression(argument.value)
                let return_type = ast.get_return_type_from_type(call.callee.ty)
                let result_type: Option[bc.Type] = Option.None()
                if not ast.is_void_type(return_type):
                    result_type = Option.Some(this.get_bc_type(return_type))
                this.emit(Instruction.Call(n_args: call.arguments.len(), result_type))
            GetAttr(base, attr):
                this.gen_expression(base)
                # TODO: optionally cast from void to type (type erasure)
                let index = get_attr_index(ty: base.ty, attr)
                this.emit(Instruction.GetAttr(index, ty: this.get_bc_type(expression.ty)))
            GetIndex(base, indici):
                this.gen_expression(base)
                panic("TODO: get-index")
            Binop(binop):
                case binop.op:
                    And:
                        this.condition_as_value(condition: expression)
                    Or:
                        this.condition_as_value(condition: expression)
                else:
                    this.gen_expression(binop.lhs)
                    this.gen_expression(binop.rhs)
                    case binop.op:
                        Add:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.Add()))
                        Sub:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.Sub()))
                        Mul:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.Multiply()))
                        Div:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.Divide()))
                        NotEquals:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.NotEquals()))
                        Equals:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.Equals()))
                        Greater:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.Greater()))
                        GreaterEquals:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.GreaterEquals()))
                        Less:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.Less()))
                        LessEquals:
                            this.emit(Instruction.Binop(op: bc.BinaryOperator.LessEquals()))
                        And:
                            panic("unreachable: and")
                        Or:
                            panic("unreachable: or")

            Unop(op, value):
                this.gen_expression(value)
                case op:
                    Not:
                        this.emit(Instruction.Not())
                    Minus:
                        this.emit(Instruction.Neg())
            IntLiteral(value):
                this.emit(Instruction.Literal(bc.LiteralValue.Int(value)))
            FloatLiteral(value):
                this.emit(Instruction.Literal(bc.LiteralValue.Float(value)))
            StringLiteral(value):
                this.emit(Instruction.Literal(bc.LiteralValue.Str(value)))
            CharLiteral(value):
                panic("TODO: char literal")
            BoolLiteral(value):
                this.emit(Instruction.Literal(bc.LiteralValue.Bool(value)))
            VarRef(variable):
                let var_index = this.get_local_index(variable)
                this.emit(Instruction.LocalGet(var_index))
            FunctionRef(function_def, type_arguments):
                this.emit(Instruction.LoadFunc(name: function_def.id.name))
            LoadSymbol(symbol):
                case symbol:
                    ExternFunction(e):
                        this.emit(Instruction.LoadFunc(name: e.name))
                    Parameter(parameter_def):
                        let parameter_index = this.get_parameter_index(parameter_def)
                        this.emit(Instruction.ParameterGet(parameter_index))
                else:
                    panic("Cannot load symbol {ast.symbol_to_str(symbol)}")
            NameRef(name):
                panic("Names must be resolved: {name}")
            Undefined:
                panic("Undefined value!")
            StructLiteral(ty, values):
                for value in values:
                    this.gen_expression(value)
                let struct_def = ast.get_struct_def_from_type(ty)
                let struct_index = option_unwrap(this.struct_mapping.get(key: ast.node_id_to_string(struct_def.id)))
                this.emit(Instruction.StructLiteral(struct_index))
            UnionLiteral(ty, field, value):
                this.gen_expression(value)
                let struct_def = ast.get_struct_def_from_type(ty)
                let struct_index = option_unwrap(this.struct_mapping.get(key: ast.node_id_to_string(struct_def.id)))
                let field_index = get_attr_index(ty, attr: field)
                this.emit(Instruction.UnionLiteral(struct_index, field_index))
            ArrayLiteral(values):
                for value in values:
                    this.gen_expression(value)
                this.emit(Instruction.ArrayLiteral(n_values: values.len()))
            TypeCast(ty, value):
                this.gen_expression(value)
                if ast.is_int_type(value.ty) and ast.is_float_type(ty):
                    this.emit(Instruction.IntToFloat())
                else:
                    panic("TODO: unsupported type-casting")
            ClassLiteral(ty, arguments):
                print("Not supported: class literal")
            ToString(value):
                panic("ToString not supported, rewrite language construct")
            Typ(ty):
                panic("Invalid expression: TYPE")
            TypeConstructor(ty):
                panic("Invalid expression: TYPE-CONSTRUCTOR")
            Variant(ty, v):
                panic("Invalid expression: Variant")
            EnumLiteral(ty, v, values):
                panic("Invalid expression: EnumLiteral")

    fn new_label() -> int:
        return this.gen_id()

    fn set_label(label?: int):
        let index = this.code.len()
        this.label_mapping.insert(key: "{label}", value: index)
        this.is_reachable = true
    
    fn translate_label(label?: int) -> int:
        return option_unwrap(this.label_mapping.get(key: "{label}"))

    fn get_relocated_instructions() -> List[Instruction]:
        # Apply relocations to labels
        let instructions: List[Instruction] = List()
        for instruction in this.code:
            case instruction:
                Jump(label):
                    label = this.translate_label(label)
                    instructions.append(Instruction.Jump(label))
                JumpIf(label1, label2):
                    label1 = this.translate_label(label1)
                    label2 = this.translate_label(label2)
                    instructions.append(Instruction.JumpIf(label1, label2))
            else:
                instructions.append(instruction)
        return instructions

    fn jump(label?: int):
        this.emit(Instruction.Jump(target: label))
        this.is_reachable = false

    fn jump_if(label: int, label2: int):
        this.emit(Instruction.JumpIf(label1: label, label2))
        this.is_reachable = false

    fn add_local(variable: ast.Variable) -> int:
        # Add a local variable!
        let ty = this.get_bc_type(variable.ty)
        let index = this.local_variables.len()
        this.local_variables.append(ty)
        this.local_var_mapping.insert(key: ast.node_id_to_string(variable.id), value: index)
        return index
    
    fn get_local_index(variable: ast.Variable) -> int:
        return option_unwrap(this.local_var_mapping.get(key: ast.node_id_to_string(variable.id)))

    fn get_parameter_index(parameter_def: ast.ParameterDef) -> int:
        return option_unwrap(this.local_var_mapping.get(key: ast.node_id_to_string(parameter_def.id)))

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
            let index = option_unwrap(this.struct_mapping.get(key: ast.node_id_to_string(struct_def.id)))
            ty = bc.Type.StructRef(index)
        elif ast.is_function_type(ty2):
            let parameter_types2 = ast.get_parameter_types_from_type(ty2)
            let parameter_types: List[bc.Type] = List()
            for p2 in parameter_types2:
                parameter_types.append(this.get_bc_type(p2))
            ty = bc.Type.Function(parameter_types)
        elif ast.is_type_parameter_type(ty2):
            ty = bc.Type.Ptr()
        elif ast.is_bool_type(ty2):
            ty = bc.Type.Int()
        else:
            panic("Type: {ast.type_to_string(ty2)} not supported")
        return ty

    fn emit(instruction?: Instruction):
        # print("Inst: {instruction_to_string(instruction)}")
        if this.is_reachable:
            this.code.append(instruction)

    fn gen_id() -> int:
        let x = this.id_counter
        this.id_counter += 1
        return x


fn get_attr_index(ty: ast.Type, attr: str) -> int:
    let struct_def = ast.get_struct_def_from_type(ty)
    let index = 0
    for field in struct_def.fields:
        if field.name == attr:
            return index
        index += 1
    panic("No field: {attr}")