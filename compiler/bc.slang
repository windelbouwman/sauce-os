
from datatypes import List

struct Program:
    functions: List[Function]

fn new_program() -> Program:
    let p = Program:
        functions: List()
    return p

struct Function:
    instructions: List[Instruction]

enum Instruction:
    Nop
    Dup  # Duplicate stack top
    Int(value: int)
    Str(value: str)
    Float(value: float)
    Bool(value: bool)
    Not
    Jump(label: int)  # Unconditional jump
    JumpIf(label1: int, label2: int)
    Call(n_arguments: int)
    Return(n_values: int)
    LocalGet(index: int)
    LocalSet(index: int)
    GetAttr(index: int)
    SetAttr(index: int)
    LoadFunc(name: str)
    StructLiteral(n_values: int)

fn instruction_to_string(instruction: Instruction) -> str:
    case instruction:
        Nop:
            return "nop"
        Dup:
            return "dup"
        Int(v):
            return "int({v})"
        Float(v):
            return "float(....)"
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
        Not:
            return "not"
        Call(n):
            return "call({n})"
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
        LoadFunc(name):
            return "load-func({name})"
        StructLiteral(count):
            return "struct-literal({count})"

