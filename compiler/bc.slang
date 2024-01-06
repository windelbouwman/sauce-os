
from std import print, float_to_str
from datatypes import List, Option
from vectype import Vector
from utils import panic

struct Program:
    extern_functions: List[ExternFunction]
    globals: List[Global]
    structs: List[Struct]
    functions: List[Function]

struct Global:
    name: str
    ty: Type
    value: Vector[Instruction]

struct Struct:
    is_union: bool
    fields: List[Type]

struct ExternFunction:
    name: str
    parameters: List[Type]
    return_type: Option[Type]
    no_return: bool

struct Function:
    name: str
    parameters: List[Type]
    return_type: Option[Type]
    no_return: bool
    locals: List[Type]
    instructions: Vector[Instruction]

enum Type:
    Int
    Float
    Str
    Char
    Ptr
    StructRef(index: int)
    Array(element_type: Type)
    Function(parameter_types: List[Type], return_type: Option[Type])

fn get_element_type_from_type(ty?: Type) -> Type:
    case ty:
        Array(element_type):
            return element_type
    else:
        panic("get_element_type_from_type: No array type")

enum Instruction:
    Nop
    Dup  # Duplicate stack top
    
    Literal(literal: LiteralValue)

    Not
    Neg

    Binop(op: BinaryOperator)
    Comparison(op: ComparisonOperator)
    Bitop(op: BitOperator)

    IntToFloat
    FloatToInt

    ToOpaque(ty: Type)
    FromOpaque(ty: Type)

    Jump(label: int)  # Unconditional jump
    JumpIf(label1: int, label2: int)
    Call(index: int)
    CallExtern(index: int)
    CallIndirect(parameter_types: List[Type], return_type: Option[Type])  # Call function pointer, on top of stack
    Return(n_values: int)
    SetupTry(try_label: int, except_label: int)
    Raise
    PopTry
    GetExceptionValue
    Unreachable

    LocalGet(index: int)
    LocalSet(index: int)
    ParameterGet(index: int)
    ParameterSet(index: int)
    GetAttr(index: int, ty: Type)  # TODO: in theory we can derive type from the value on the stack + index?
    SetAttr(index: int)
    GetIndex
    SetIndex

    GlobalGet(index: int)
    GlobalSet(index: int)

    LoadFunc(index: int)

    StructLiteral(struct_index: int)
    UnionLiteral(struct_index: int, field_index: int)
    ArrayLiteral(size: int)
    ArrayLiteral2

enum LiteralValue:
    Int(value: int)
    Str(value: str)
    Float(value: float)
    Bool(value: bool)
    Char(value: char)

enum BinaryOperator:
    Add
    Sub
    Divide
    Multiply

enum ComparisonOperator:
    Less
    LessEquals
    Greater
    GreaterEquals
    Equals
    NotEquals

enum BitOperator:
    Shr
    Shl
    Xor
    And
    Or

fn literal_to_string(literal?: LiteralValue) -> str:
    case literal:
        Int(value):
            return "int({value})"
        Float(value):
            return "float({float_to_str(value)})"
        Str(value):
            return "str('{value}')"
        Bool(value):
            if value:
                return "bool(true)"
            else:
                return "bool(false)"
        Char(value):
            return "char('{value}')"


fn instruction_to_string(instruction?: Instruction) -> str:
    case instruction:
        Nop:
            return "nop"
        Dup:
            return "dup"
        Literal(literal):
            return literal_to_string(literal)
        Jump(v):
            return "jump({v})"
        JumpIf(v1, v2):
            return "jump-if({v1}, {v2})"
        Not:
            return "not"
        Neg:
            return "neg"
        Binop(op):
            return binop_to_string(op)
        Comparison(op):
            return comparison_to_string(op)
        Bitop(op):
            return bitop_to_string(op)

        IntToFloat:
            return "int-to-float"
        FloatToInt:
            return "float-to-int"

        ToOpaque(t):
            return "?-to-opaque"
        FromOpaque(t):
            return "opaque-to-?"

        Call(index):
            return "call({index})"
        CallExtern(index):
            return "call-extern({index})"
        CallIndirect(parameter_types, return_type):
            return "call-indirect({parameter_types.len()})"
        Return(v):
            return "return({v})"
        Unreachable:
            return "unreachable"
        SetupTry(try_label, except_label):
            return "setup-try(try: {try_label}, except: {except_label})"
        Raise:
            return "raise"
        PopTry:
            return "pop-try"
        GetExceptionValue:
            return "get-exception-value"
        LocalGet(index):
            return "local-get({index})"
        LocalSet(index):
            return "local-set({index})"
        GlobalGet(index):
            return "global-get({index})"
        GlobalSet(index):
            return "global-set({index})"
        ParameterGet(index):
            return "parameter-get({index})"
        ParameterSet(index):
            return "parameter-set({index})"
        GetAttr(index, ty):
            return "get-attr({index}) -> {type_to_string(ty)}"
        SetAttr(index):
            return "set-attr({index})"
        GetIndex:
            return "get-index"
        SetIndex:
            return "set-index"
        LoadFunc(index):
            return "load-func({index})"
        StructLiteral(struct_index):
            return "struct-literal(index={struct_index})"
        UnionLiteral(struct_index, field_index):
            return "union-literal(index={struct_index}, field={field_index})"
        ArrayLiteral(count):
            return "array-literal({count})"
        ArrayLiteral2:
            return "array-literal2"

fn binop_to_string(op: BinaryOperator) -> str:
    case op:
        Add:
            return "add"
        Sub:
            return "sub"
        Divide:
            return "div"
        Multiply:
            return "mul"

fn comparison_to_string(op: ComparisonOperator) -> str:
    case op:
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

fn bitop_to_string(op: BitOperator) -> str:
    case op:
        Shr:
            return "bit-shr"
        Shl:
            return "bit-shr"
        Xor:
            return "bit-xor"
        And:
            return "bit-and"
        Or:
            return "bit-or"

fn print_bc_program(program: Program):
    print("BYTECODE program")
    let index = 0
    let func_index = 0

    for extern_function in program.extern_functions:
        print("  EXTERN FUNC {func_index} {extern_function.name}")
        func_index += 1

    for struct0 in program.structs:
        print("  STRUCT {index}")
        for field in struct0.fields:
            print("    -> {type_to_string(ty: field)}")
        index += 1

    for global in program.globals:
        print("  GLOBAL {global.name} {type_to_string(global.ty)}")
        index = 0
        for instruction in global.value:
            print("      {index}: {instruction_to_string(instruction)}")
            index += 1

    func_index = 0
    for function in program.functions:
        print("  FUNC {func_index}: {function.name}")
        func_index += 1
        print("    PARAMETERS:")
        for ty in function.parameters:
            print("      > {type_to_string(ty)}")
        case function.return_type:
            Some(ty):
                print("    RETURNS: {type_to_string(ty)}")
            None:
                pass
        print("    LOCALS:")
        for ty in function.locals:
            print("      > {type_to_string(ty)}")
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
        Char:
            return "char"
        StructRef(index):
            return "struct-ref({index})"
        Function(parameter_types, return_type):
            return "func-ptr(...)"
        Array(element_type):
            return "array({type_to_string(element_type)})"
