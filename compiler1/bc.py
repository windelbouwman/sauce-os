"""
Bytecode
"""

from enum import Enum


class Program:
    """A bytecode program"""

    def __init__(self, types: list["StructTyp"], globals, functions: list["Function"]):
        self.types = types
        self.globals = globals
        self.functions = functions


class SimpleTyp(Enum):
    VOID = 1
    INT = 3
    FLOAT = 4
    STR = 5
    BOOL = 7
    CHAR = 8
    PTR = 10


class Typ:
    def __init__(self, kind):
        self.kind = kind


class BaseTyp(Typ):
    def __init__(self, type_id: SimpleTyp):
        self.type_id = type_id

    def __repr__(self):
        return f"{self.type_id}"


class ArrayTyp(Typ):
    def __init__(self, element_typ: Typ, size: int):
        self.element_typ = element_typ
        self.size = size


class FunctionType(Typ):
    def __init__(self, parameter_types: list[Typ], return_type: Typ):
        self.parameter_types = parameter_types
        self.return_type = return_type


class StructTyp(Typ):
    def __init__(self, index: int):
        self.index = index


class StructTypDef:
    def __init__(self, name: str, fields):
        self.name = name
        self.fields = fields


class Function:
    def __init__(
        self,
        name: str,
        code,
        params: list["Typ"],
        local_vars: list["Typ"],
        return_ty: Typ,
    ):
        self.name = name
        self.code = code
        self.params = params
        self.local_vars = local_vars
        self.return_ty = return_ty


class OpCode(Enum):
    UNREACHABLE = 7
    CONST = 8
    DUP = 9
    JUMP = 10
    JUMP_IF = 11
    RETURN = 12
    LOCAL_SET = 13
    LOCAL_GET = 14
    CALL = 15
    GET_ATTR = 16
    SET_ATTR = 17
    GET_INDEX = 18
    SET_INDEX = 19
    BUILTIN = 20
    LOADFUNC = 21
    CAST = 22
    GLOBAL_GET = 23
    GLOBAL_SET = 24

    RAISE = 26
    SETUP_EXCEPT = 27
    POP_EXCEPT = 28

    ADD = 40
    SUB = 41
    MUL = 42
    DIV = 43

    NEG = 45

    LT = 50
    GT = 51
    LTE = 52
    GTE = 53
    EQ = 54

    AND = 55
    OR = 56
    NOT = 57

    STRUCT_LITERAL = 70
    ARRAY_LITERAL = 72
    ARRAY_LITERAL2 = 73


def print_bytecode(program: Program, f=None):
    print("===[ bytecode ]===")
    for ty in program.types:
        print(f"type: {ty}")
    print("Globals")
    for idx, g in enumerate(program.globals):
        print(f"  {idx}: {g}")
    for function in program.functions:
        print(
            f"func {function.name} params={function.params} locals={function.local_vars} ret={function.return_ty}",
            file=f,
        )
        for pc, inst in enumerate(function.code):
            opcode, operands = inst
            print(f"  {pc}: {opcode} {operands}", file=f)
