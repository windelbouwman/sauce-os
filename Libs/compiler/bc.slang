
from std import print, float_to_str
from datatypes import List, Option
from settype import IntegerSet
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
    value: Option[Vector[Instruction]]

struct Struct:
    name: str
    fields: List[TypedName]

struct TypedName:
    ty: Type
    name: str

struct ExternFunction:
    name: str
    parameters: List[TypedName]
    return_type: Option[Type]
    no_return: bool

struct Function:
    name: str
    parameters: List[TypedName]
    return_type: Option[Type]
    no_return: bool
    locals: List[TypedName]
    instructions: Vector[Instruction]

enum Type:
    Int(signed: bool, bits: int)
    Float(bits: int)
    Bool
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

    IntCast(signed: bool, bits: int)
    IntToFloat
    FloatToInt

    ToOpaque(ty: Type)
    FromOpaque(ty: Type)

    Jump(label: int)  # Unconditional jump
    JumpIf(label1: int, label2: int)
    Call(index: int)
    CallIndirect(parameters: List[TypedName], return_type: Option[Type])  # Call function pointer, on top of stack
    Return(n_values: int)
    SetupTry(try_label: int, except_label: int)
    Raise
    PopTry
    DecRef(index: int)
    GetExceptionValue
    Unreachable

    LocalGet(index: int)
    LocalSet(index: int)
    ParameterGet(index: int)
    ParameterSet(index: int)
    GetAttr(index: int)
    SetAttr(index: int)
    GetIndex
    SetIndex

    GlobalGet(index: int)
    GlobalSet(index: int)

    LoadFunc(index: int)

    StructLiteral(struct_index: int)
    ArrayLiteral(size: int)
    ArrayLiteral2(ty: Type)

fn get_target_labels(instructions: Vector[Instruction]) -> IntegerSet:
    """ Get a set of labels to which is being jumped """
    let target_labels = IntegerSet()
    for instruction in instructions:
        case instruction:
            Jump(index):
                target_labels.add(index)
            JumpIf(index1, index2):
                target_labels.add(index1)
                target_labels.add(index2)
            SetupTry(try_label, except_label):
                target_labels.add(try_label)
                target_labels.add(except_label)
        else:
            pass
    return target_labels

enum LiteralValue:
    Int(value: int)
    Str(value: str)
    Float(value: float)
    Bool(value: bool)
    Char(value: char)
    Null

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
            "int({value})"
        Float(value):
            "float({float_to_str(value)})"
        Str(value):
            "str('{value}')"
        Bool(value):
            if value:
                "bool(true)"
            else:
                "bool(false)"
        Char(value):
            "char('{value}')"
        Null:
            "Null"


fn instruction_to_string(instruction?: Instruction) -> str:
    case instruction:
        Nop:
            "nop"
        Dup:
            "dup"
        Literal(literal):
            literal_to_string(literal)
        Jump(v):
            "jump({v})"
        JumpIf(v1, v2):
            "jump-if({v1}, {v2})"
        Not:
            "not"
        Neg:
            "neg"
        Binop(op):
            binop_to_string(op)
        Comparison(op):
            comparison_to_string(op)
        Bitop(op):
            bitop_to_string(op)
        IntCast(signed, bits):
            if signed:
                "to-int{bits}"
            else:
                "to-uint{bits}"
        IntToFloat:
            "int-to-float"
        FloatToInt:
            "float-to-int"

        ToOpaque(t):
            "?-to-opaque"
        FromOpaque(t):
            "opaque-to-?"

        Call(index):
            "call({index})"
        CallIndirect(parameter_types, return_type):
            "call-indirect({parameter_types.len()})"
        Return(v):
            "return({v})"
        Unreachable:
            "unreachable"
        SetupTry(try_label, except_label):
            "setup-try(try: {try_label}, except: {except_label})"
        Raise:
            "raise"
        PopTry:
            "pop-try"
        DecRef(index):
            "dec ref {index}"
        GetExceptionValue:
            "get-exception-value"
        LocalGet(index):
            "local-get({index})"
        LocalSet(index):
            "local-set({index})"
        GlobalGet(index):
            "global-get({index})"
        GlobalSet(index):
            "global-set({index})"
        ParameterGet(index):
            "parameter-get({index})"
        ParameterSet(index):
            "parameter-set({index})"
        GetAttr(index):
            "get-attr({index})"
        SetAttr(index):
            "set-attr({index})"
        GetIndex:
            "get-index"
        SetIndex:
            "set-index"
        LoadFunc(index):
            "load-func({index})"
        StructLiteral(struct_index):
            "struct-literal(index={struct_index})"
        ArrayLiteral(count):
            "array-literal({count})"
        ArrayLiteral2(ty):
            "array-literal2"

fn binop_to_string(op: BinaryOperator) -> str:
    case op:
        Add:
            "add"
        Sub:
            "sub"
        Divide:
            "div"
        Multiply:
            "mul"

fn comparison_to_string(op: ComparisonOperator) -> str:
    case op:
        Less:
            "lt"
        LessEquals:
            "lte"
        GreaterEquals:
            "gte"
        Greater:
            "gt"
        Equals:
            "eq"
        NotEquals:
            "ne"

fn bitop_to_string(op: BitOperator) -> str:
    case op:
        Shr:
            "bit-shr"
        Shl:
            "bit-shr"
        Xor:
            "bit-xor"
        And:
            "bit-and"
        Or:
            "bit-or"

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
            print("    -> {field.name}: {type_to_string(ty: field.ty)}")
        index += 1

    for global in program.globals:
        print("  GLOBAL {global.name} {type_to_string(global.ty)}")
        case global.value:
            Some(value):
                print_bc_instructions(instructions: value)
            None:
                pass

    for function in program.functions:
        print("  FUNC {func_index}: {function.name}")
        func_index += 1
        print("    PARAMETERS:")
        for parameter in function.parameters:
            print("      > {parameter.name}: {type_to_string(ty: parameter.ty)}")
        case function.return_type:
            Some(ty):
                print("    RETURNS: {type_to_string(ty)}")
            None:
                pass
        print("    LOCALS:")
        for local in function.locals:
            print("      > {local.name}: {type_to_string(ty: local.ty)}")
        print("    CODE:")
        print_bc_instructions(instructions: function.instructions)

fn print_bc_instructions(instructions: Vector[Instruction]):
    let index = 0
    for instruction in instructions:
        print("      {index}: {instruction_to_string(instruction)}")
        index += 1

fn type_to_string(ty?: Type) -> str:
    case ty:
        Int(signed, bits):
            if signed:
                "int{bits}"
            else:
                "uint{bits}"
        Float(bits):
            "float{bits}"
        Bool:
            "bool"
        Ptr:
            "ptr"
        Str:
            "str"
        Char:
            "char"
        StructRef(index):
            "struct-ref({index})"
        Function(parameter_types, return_type):
            "func-ptr(...)"
        Array(element_type):
            "array({type_to_string(element_type)})"
