"""
Bytecode
"""

from enum import Enum


class Program:
    """A bytecode program"""

    def __init__(self, functions: list["Function"]):
        self.functions = functions


class Function:
    def __init__(self, name: str, code, n_locals: int):
        self.name = name
        self.code = code
        self.n_locals = n_locals  # locals + parameters!


class OpCode(Enum):
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

    ADD = 40
    SUB = 41
    MUL = 42
    DIV = 43

    LT = 50
    GT = 51
    LTE = 52
    GTE = 53
    EQ = 54

    AND = 55
    OR = 56
    NOT = 57
