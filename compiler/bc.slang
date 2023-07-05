
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
    Int(int)
    Str(str)
    Float(float)
    Not
    Bool(bool)
    Jump(int)  # Unconditional jump
    JumpIf(int, int)
    Call(int)
    Return(int)
    LocalGet(int)
    LocalSet(int)
    GetAttr(int)
    SetAttr(int)
    LoadFunc(str)
    StructLiteral(int)

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

