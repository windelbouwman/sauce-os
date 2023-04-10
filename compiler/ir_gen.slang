# generate bytecode

import ast
from std import print
from datatypes import List
from utils import panic

enum Instruction:
    Nop
    Dup  # Duplicate stack top
    Int(int)
    Str(str)
    Bool(bool)
    Jump(int)  # Unconditional jump
    JumpIf(int, int)
    Return(int)
    LocalGet(int)
    LocalSet(int)
    GetAttr(int)
    SetAttr(int)

fn instruction_to_string(instruction: Instruction) -> str:
    case instruction:
        Nop:
            return "nop"
        Dup:
            return "dup"
        Int(v):
            return "int({v})"
        Str(v):
            return "str({v})"
        Bool(v):
            if v:
                return "bool(true)"
            else:
                return "bool(false)"
        Jump(v):
            return "jump({v})"
        JumpIf(v1, v2):
            return "jump-if({v1}, {v2})"
        Return(v):
            return "return({v})"
        LocalGet(v):
            return "local-get({v})"
        LocalSet(v):
            return "local-set({v})"
        GetAttr(v):
            return "get-attr({v})"
        SetAttr(v):
            return "set-attr({v})"

enum Value:
    Int(int)
    Str(str)
    Bool(bool)


class Frame:
    var locals: List[Value] = List()
    var stack: List[Value] = List()

class VM:
    var frames: List[Frame] = List()

    fn tick(instruction: Instruction):
        case instruction:
            Nop:
                pass
            Dup:
                let val = this.pop()
                this.push(val)
                this.push(val)
            Int(val):
                this.push(Value::Int(val))
            Str(val):
                this.push(Value::Str(val))
            Bool(val):
                this.push(Value::Bool(val))
            LocalGet(index):
                let val = this.frames.last().locals.get(index)
                this.push(val)
            LocalSet(index):
                panic("TODO")
            GetAttr(index):
                let base = this.pop()
                panic("TODO")
            SetAttr(index):
                let value = this.pop()
                let base = this.pop()
                panic("TODO")
            Jump(target):
                panic("TODO")
            JumpIf(target, target2):
                panic("TODO")
            Return(amount):
                if amount == 1:
                    let val = this.pop()
                panic("Return not impl")
    
    fn push(value: Value):
        this.frames.last().stack.append(value)
    
    fn pop() -> Value:
        return this.frames.last().stack.pop_last()


fn gen_bytecode(module: ast.Module):
    print("Generating bytecode for {module.name}")
    let g = Generator()
    g.gen_prog(module)

class Generator:
    var id_counter: int = 1

    fn gen_prog(prog: ast.Module):
        for definition in prog.definitions:
            case definition:
                Function(function_def):
                    this.gen_func(function_def)

    fn gen_func(func: ast.FunctionDef):
        this.gen_statement(func.body)

    fn gen_statement(statement: ast.Statement):
        case statement.kind:
            Pass:
                pass
            Break:
                this.jump(1)
            Continue:
                this.jump(1)
            Expr(expr):
                this.gen_expression(expr)
            While(whilly):
                let test_label = this.new_label()
                let body_label = this.new_label()
                let final_label = this.new_label()

                this.set_label(test_label)
                this.gen_expression(whilly.condition)
                this.jump_if(body_label, final_label)

                this.set_label(body_label)
                this.gen_statement(whilly.body)
                this.jump(test_label)

                this.set_label(final_label)
            If(iffy):
                let true_label = this.new_label()
                let false_label = this.new_label()
                let final_label = this.new_label()

                this.gen_expression(iffy.condition)
                this.jump_if(true_label, false_label)
                
                this.set_label(true_label)
                this.gen_statement(iffy.true_body)
                this.jump(final_label)

                this.set_label(false_label)
                this.gen_statement(iffy.false_body)
                this.jump(final_label)

                this.set_label(final_label)
            Loop(loopy):
                panic("Loop not implemented")
            Let(letty):
                this.gen_expression(letty.value)
                # TODO: var index!
                let var_index = 0
                this.emit(Instruction::LocalSet(var_index))
                panic("Let not implemented")
            Compound(inner):
                for s in inner:
                    this.gen_statement(s)
            Switch(switchy):
                panic("Switch not implemented")
            Return(opt_val):
                case opt_val:
                    Some(val):
                        this.gen_expression(val)
                        this.emit(Instruction.Return(1))
                    None:
                        this.emit(Instruction.Return(0))
    
    fn gen_expression(expression: ast.Expression):
        case expression.kind:
            Call(call):
                this.gen_expression(call.callee)
                for argument in call.arguments:
                    this.gen_expression(argument)
            GetAttr(base,attr):
                this.gen_expression(base)
                # TODO: determine index!
                let index = 0
                this.emit(Instruction.GetAttr(index))
            Binop(binop):
                this.gen_expression(binop.lhs)
                this.gen_expression(binop.rhs)

            IntLiteral(value):
                this.emit(Instruction::Int(value))
            StringLiteral(value):
                this.emit(Instruction::Str(value))
            BoolLiteral(value):
                this.emit(Instruction::Bool(value))
            VarRef(v):
                # TODO: var index!
                let var_index = 0
                this.emit(Instruction::LocalGet(var_index))
            NameRef(name):
                panic("Names must be resolved: {name}")
            Undefined:
                panic("Undefined value!")


    fn new_label() -> int:
        return this.gen_id()

    fn set_label(label: int):
        pass

    fn jump(label: int):
        this.emit(Instruction::Jump(label))

    fn jump_if(label: int, label2: int):
        this.emit(Instruction::JumpIf(label, label2))

    fn emit(instruction: Instruction):
        print("Inst: {instruction_to_string(instruction)}")

    fn gen_id() -> int:
        let x = this.id_counter
        this.id_counter += 1
        return x

