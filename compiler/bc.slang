
from std import print
from datatypes import List, Option

struct Program:
    structs: List[Struct]
    functions: List[Function]

struct Struct:
    fields: List[Type]

struct Function:
    name: str
    parameters: List[Type]
    return_type: Option[Type]
    locals: List[Type]
    instructions: List[Instruction]

enum Type:
    Int
    Float
    Str
    Ptr
    StructRef(index: int)

enum Instruction:
    Nop
    Dup  # Duplicate stack top
    
    Literal(literal: LiteralValue)

    Not
    Neg

    Binop(op: BinaryOperator)

    Jump(label: int)  # Unconditional jump
    JumpIf(label1: int, label2: int)
    Call(n_arguments: int, result_type: Option[Type])
    Return(n_values: int)
    LocalGet(index: int)
    LocalSet(index: int)
    ParameterGet(index: int)
    GetAttr(index: int, ty: Type)  # TODO: in theory we can derive type from the value on the stack + index?
    SetAttr(index: int)

    LoadFunc(name: str)

    StructLiteral(struct_index: int)
    UnionLiteral(field: int)
    ArrayLiteral(size: int)

enum LiteralValue:
    Int(value: int)
    Str(value: str)
    Float(value: float)
    Bool(value: bool)

enum BinaryOperator:
    Add
    Sub
    Divide
    Multiply

    Less
    LessEquals
    Greater
    GreaterEquals
    Equals
    NotEquals

fn instruction_to_string(instruction: Instruction) -> str:
    case instruction:
        Nop:
            return "nop"
        Dup:
            return "dup"
        Literal(literal):
            case literal:
                Int(v):
                    return "int({v})"
                Float(v):
                    return "float(....)"
                Str(v):
                    return "str('{v}')"
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
        Neg:
            return "neg"
        
        Binop(op):
            case op:
                Add:
                    return "add"
                Sub:
                    return "sub"
                Divide:
                    return "div"
                Multiply:
                    return "mul"
                Less:
                    return "lt"
                LessEquals:
                    return "lte"
                GreaterEquals:
                    return "gte"
                Greater:
                    return "gt"
                Equals:
                    return "eq"
                NotEquals:
                    return "ne"

        Call(n, r):
            return "call({n})"
        Return(v):
            return "return({v})"
        LocalGet(index):
            return "local-get({index})"
        LocalSet(index):
            return "local-set({index})"
        ParameterGet(index):
            return "parameter-get({index})"
        GetAttr(index, ty):
            return "get-attr({index}) -> {type_to_string(ty)}"
        SetAttr(index):
            return "set-attr({index})"
        LoadFunc(name):
            return "load-func({name})"
        StructLiteral(struct_index):
            return "struct-literal(index={struct_index})"
        UnionLiteral(field):
            return "union-literal({field})"
        ArrayLiteral(count):
            return "array-literal({count})"


fn print_bc_program(program: Program):
    print("BYTECODE program")
    let index = 0

    for struct0 in program.structs:
        print("  STRUCT {index}")
        for field in struct0.fields:
            print("    -> {type_to_string(ty: field)}")
        index += 1

    for function in program.functions:
        print("  FUNC: {function.name}")
        print("    PARAMETERS:")
        for ty1 in function.parameters:
            print("      > {type_to_string(ty1)}")
        case function.return_type:
            Some(ty):
                print("    RETURNS: type_to_string(ty)")
            None:
                pass
        print("    LOCALS:")
        for ty2 in function.locals:
            print("      > {type_to_string(ty2)}")
        print("    CODE:")
        index = 0
        for instruction in function.instructions:
            print("      {index}: {instruction_to_string(instruction)}")
            index += 1

fn type_to_string(ty?: Type) -> str:
    case ty:
        Int:
            return "int"
        Float:
            return "float"
        Ptr:
            return "ptr"
        Str:
            return "str"
        StructRef(index):
            return "struct-ref({index})"
