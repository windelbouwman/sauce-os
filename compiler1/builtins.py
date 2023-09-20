""" A set of builtin functions.

"""

from . import ast


def std_module() -> ast.Module:
    mod = ast.Module("std", [], [])
    mod.add_definition(
        "print", ast.BuiltinFunction("std_print", [ast.str_type], ast.void_type)
    )
    mod.add_definition(
        "exit", ast.BuiltinFunction("std_exit", [ast.int_type], ast.void_type)
    )
    mod.add_definition(
        "int_to_str",
        ast.BuiltinFunction("std_int_to_str", [ast.int_type], ast.str_type),
    )
    mod.add_definition(
        "str_to_int",
        ast.BuiltinFunction("std_str_to_int", [ast.str_type], ast.int_type),
    )
    mod.add_definition(
        "read_file", ast.BuiltinFunction("std_read_file", [ast.str_type], ast.str_type)
    )

    mod.add_definition(
        "float_to_str",
        ast.BuiltinFunction("std_float_to_str", [ast.float_type], ast.str_type),
    )
    mod.add_definition(
        "str_to_float",
        ast.BuiltinFunction("std_str_to_float", [ast.str_type], ast.float_type),
    )

    mod.add_definition(
        "str_len",
        ast.BuiltinFunction("std_str_len", [ast.str_type], ast.int_type),
    )

    mod.add_definition(
        "str_get",
        ast.BuiltinFunction("std_str_get", [ast.str_type, ast.int_type], ast.str_type),
    )

    mod.add_definition(
        "str_slice",
        ast.BuiltinFunction(
            "std_str_slice", [ast.str_type, ast.int_type, ast.int_type], ast.str_type
        ),
    )

    mod.add_definition(
        "ord",
        ast.BuiltinFunction("std_ord", [ast.str_type], ast.int_type),
    )

    mod.add_definition(
        "chr",
        ast.BuiltinFunction("std_chr", [ast.int_type], ast.str_type),
    )

    mod.add_definition(
        "get_n_args",
        ast.BuiltinFunction("std_get_n_args", [], ast.int_type),
    )

    mod.add_definition(
        "get_arg",
        ast.BuiltinFunction("std_get_arg", [ast.int_type], ast.str_type),
    )

    return mod


def get_builtins(args=(), stdout=None):
    def std_read_file(filename: str) -> str:
        with open(filename, "r") as f:
            return f.read()

        # return "bla   bla 1237 ]"

    if stdout:

        def std_print(txt: str):
            print(txt, file=stdout)

    else:

        def std_print(txt: str):
            print(txt)

    def std_exit(code: int):
        raise RuntimeError(f"EXIT with code: {code}")

    def get_n_args():
        return len(args)

    def get_arg(index):
        return args[index]

    return {
        "std_print": std_print,
        "std_exit": std_exit,
        "std_read_file": std_read_file,
        "std_int_to_str": str,
        "std_str_to_int": int,
        "std_float_to_str": str,
        "std_str_to_float": float,
        "std_str_len": len,
        "std_str_get": lambda s, i: s[i],
        "std_str_slice": lambda s, b, e: s[b:e],
        "std_ord": ord,
        "std_chr": chr,
        "std_get_n_args": get_n_args,
        "std_get_arg": get_arg,
    }


BUILTINS_PY_IMPL = """

import sys

def std_get_n_args() -> int:
    return len(sys.argv) - 1

def std_get_arg(index) -> str:
    return sys.argv[index + 1]

def std_read_file(filename: str) -> str:
    with open(filename, "r") as f:
        return f.read()

def std_exit(code: int):
    raise RuntimeError(f"EXIT with code: {code}")

std_print = print
std_int_to_str = str
std_str_to_int = int
std_float_to_str = str
std_str_to_float = float
std_str_len = len
std_ord = ord
std_chr = chr

def std_str_get(s, i):
    return s[i]

def std_str_slice(s,b,e):
    return s[b:e]

"""
