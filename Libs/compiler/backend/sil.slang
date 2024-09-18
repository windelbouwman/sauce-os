
# SSA IL
# Similar to QBE IL
# See: https://c9x.me/compile/doc/il.html

from std import print
from datatypes import List, Option
from strlib import str_join

class Program:
    var functions: List[Function]

    fn dump():
        print("SIL program")
        for function in functions:
            function.dump()

class Function:
    var name: str
    var start: Block
    var blocks: List[Block]

    fn to_string() -> str:
        return "function {name}()"

    fn dump():
        print("{this}")
        for block in blocks:
            block.dump()

class Block:
    var name: str
    var instructions: List[Instruction]

    fn to_string() -> str:
        return "  @{name}"

    fn dump():
        print("{this}")
        for instruction in instructions:
            print("    {instruction}")

class Instruction:
    var op: OpCode

    fn to_string() -> str:
        let txt = ""
        case op:
            Nop:
                txt = "nop"
            Binop(dst, op2, lhs, rhs):
                case op2:
                    Add:
                        txt = "add"
                    Sub:
                        txt = "sub"
                    Mul:
                        txt = "mul"
                    Div:
                        txt = "div"
                txt = "{value_to_string(dst)} = {txt} {value_to_string(lhs)}, {value_to_string(rhs)}"
            Compare(dst, op2, lhs, rhs):
                # txt = "eq/gt?"
                case op2:
                    Eq:
                        txt = "eq"
                    Neq:
                        txt = "ne"
                    Gt:
                        txt = "gt"
                    Gte:
                        txt = "gte"
                    Lt:
                        txt = "lt"
                    Lte:
                        txt = "lte"
                txt = "{value_to_string(dst)} = {txt} {value_to_string(lhs)}, {value_to_string(rhs)}"
            Alloc(addr, size):
                txt = "{value_to_string(addr)} = alloc {size}"
            Load(dst, addr):
                txt = "{value_to_string(dst)} = load {value_to_string(addr)}"
            Store(addr, value):
                txt = "store {value_to_string(addr)}, {value_to_string(value)}"
            Jump(label):
                txt = "jmp @{label}"
            JumpNonZero(condition, label1, label2):
                txt = "jmp-non-zero {value_to_string(condition)} @{label1}, @{label2}"
            Call(dst, callee, arguments):
                let parts: List[str] = List()
                for argument in arguments:
                    parts.append(value_to_string(argument))
                let args = str_join(parts, sep: ", ")
                txt = "call {value_to_string(callee)}({args})"
                case dst:
                    Some(target):
                        txt = "{value_to_string(target)} = {txt}"
                    None:
                        pass
            Return(value):
                txt = "return"
                case value:
                    Some(value2):
                        txt = "{txt} {value_to_string(value2)}"
                    None:
                        pass
            Halt:
                txt = "hlt"
        return txt

enum OpCode:
    Nop
    Binop(dst: Value, op: BinaryOp, lhs: Value, rhs: Value)
    Compare(dst: Value, op: CompOp, lhs: Value, rhs: Value)
    Alloc(addr: Value, size: int)
    Load(dst: Value, addr: Value)
    Store(addr: Value, value: Value)
    Jump(label: str)
    JumpNonZero(condition: Value, label1: str, label2: str)
    Call(dst: Option[Value], callee: Value, arguments: List[Value])
    Return(value: Option[Value])
    Halt

enum BinaryOp:
    Add
    Sub
    Mul
    Div

enum CompOp:
    Eq
    Neq
    Gt
    Lt
    Gte
    Lte

enum Value:
    Integer(value: int)
    Tmp(name: str)
    Global(name: str)

fn value_to_string(value?: Value) -> str:
    case value:
        Integer(value):
            return "{value}"
        Tmp(name):
            return "%{name}"
        Global(name):
            return "${name}"
