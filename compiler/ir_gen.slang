# generate bytecode

import ast
from std import print
from datatypes import List
from utils import panic
from bc import Instruction, instruction_to_string
import bc


fn gen_bytecode(module: ast.Module) -> bc.Program:
    print("Generating bytecode for {module.name}")
    let g = Generator()
    return g.gen_prog(module)

class Generator:
    var id_counter: int = 1
    var code: List[Instruction] = List()

    fn gen_prog(module: ast.Module) -> bc.Program:
        for definition in module.definitions:
            case definition:
                Function(function_def):
                    this.gen_func(function_def)
                ExternFunction(e):
                    pass
                Enum(e):
                    pass
                Struct(s):
                    pass
                Class(c):
                    panic("Classes are not supported, please rewrite into structs with functions.")
                Var(v):
                    panic("VAR def not impl.")

    fn gen_func(function_def: ast.FunctionDef):
        print("FUNC {function_def.id.name}:")
        this.gen_statement(function_def.body)

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            Pass:
                pass
            Break:
                this.jump(target: 1)
            Continue:
                this.jump(target: 1)
            Expr(expr):
                this.gen_expression(expr)
            Assignment(target, op, value):
                # TODO: handle optional operator, like += and -=
                this.gen_expression(value)
            While(while_statement):
                let test_label = this.new_label()
                let body_label = this.new_label()
                let final_label = this.new_label()

                this.set_label(test_label)
                this.gen_expression(while_statement.condition)
                this.jump_if(label: body_label, label2: final_label)

                this.set_label(body_label)
                this.gen_statement(while_statement.body)
                this.jump(test_label)

                this.set_label(final_label)
            If(if_statement):
                let true_label = this.new_label()
                let false_label = this.new_label()
                let final_label = this.new_label()

                this.gen_expression(if_statement.condition)
                this.jump_if(label: true_label, label2: false_label)
                
                this.set_label(true_label)
                this.gen_statement(if_statement.true_body)
                this.jump(final_label)

                this.set_label(false_label)
                this.gen_statement(if_statement.false_body)
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
                # TODO: var index!
                let var_index = 0
                this.emit(Instruction.LocalSet(var_index))
                # panic("Let not implemented")
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
            Raise(val):
                panic("Raise not implemented")
    
    fn gen_expression(expression?: ast.Expression):
        case expression.kind:
            Call(call):
                this.gen_expression(call.callee)
                for argument in call.arguments:
                    this.gen_expression(argument.value)
                this.emit(Instruction.Call(n_args: call.arguments.len()))
            GetAttr(base,attr):
                this.gen_expression(base)
                # TODO: determine index!
                let index = 0
                this.emit(Instruction.GetAttr(index))
            GetIndex(base, indici):
                this.gen_expression(base)
                panic("TODO: get-index")
            Binop(binop):
                this.gen_expression(binop.lhs)
                this.gen_expression(binop.rhs)
            Unop(op, value):
                this.gen_expression(value)
                this.emit(Instruction.Not())
            IntLiteral(value):
                this.emit(Instruction.Int(value))
            FloatLiteral(value):
                this.emit(Instruction.Float(value))
            StringLiteral(value):
                this.emit(Instruction.Str(value))
            BoolLiteral(value):
                this.emit(Instruction.Bool(value))
            VarRef(v):
                # TODO: var index!
                let var_index = 0
                this.emit(Instruction.LocalGet(var_index))
            LoadSymbol(symbol):
                case symbol:
                    #Var(v):
                        # panic("TODO: load var")
                        # this.emit(Instruction.Local(e.name))
                    ExternFunction(e):
                        this.emit(Instruction.LoadFunc(name: e.name))
                else:
                    panic("TODO: load symbol")
            NameRef(name):
                panic("Names must be resolved: {name}")
            Undefined:
                panic("Undefined value!")
            StructLiteral(ty,values):
                for value in values:
                    this.gen_expression(value)
                print("TODO: struct literal")
            ClassLiteral(ty, arguments):
                print("Not supported: class literal")
            TypeCast(ty, value):
                panic("TODO: type-casting")
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
        # TODO!
        pass

    fn jump(label?: int):
        this.emit(Instruction.Jump(target: label))

    fn jump_if(label: int, label2: int):
        this.emit(Instruction.JumpIf(label1: label, label2))

    fn emit(instruction?: Instruction):
        print("Inst: {instruction_to_string(instruction)}")

    fn gen_id() -> int:
        let x = this.id_counter
        this.id_counter += 1
        return x

