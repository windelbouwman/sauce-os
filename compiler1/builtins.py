""" A set of builtin functions.

"""

from .location import Location
from . import ast


def create_rt_module() -> ast.Module:
    modname = "rt"
    mod = ast.Module(modname, [], [])
    mod.add_definition(
        ast.BuiltinFunction(
            modname, "int_to_str", [ast.int_type], ast.str_type, Location.default()
        ),
    )
    mod.add_definition(
        ast.BuiltinFunction(
            modname, "str_to_int", [ast.str_type], ast.int_type, Location.default()
        )
    )
    mod.add_definition(
        ast.BuiltinFunction(
            modname, "char_to_str", [ast.char_type], ast.str_type, Location.default()
        )
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
        "rt_int_to_str": str,
        "std_str_to_int": int,
        "std_float_to_str": str,
        "std_str_to_float": float,
        "std_char_to_str": str,
        "std_str_len": len,
        "std_str_get": lambda s, i: s[i],
        "std_str_slice": lambda s, b, e: s[b:e],
        "rt_str_concat": lambda a, b: a + b,
        "rt_str_compare": lambda a, b: a == b,
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
rt_int_to_str = str
std_str_to_int = int
std_float_to_str = str
std_str_to_float = float
std_str_len = len
std_ord = ord
std_chr = chr

rt_char_to_str = str

def std_str_get(s, i):
    return s[i]

def std_str_slice(s,b,e):
    return s[b:e]

def std_file_open(filename: str) -> int:
    return open(filename, 'w')

def std_file_writeln(handle: int, text: str):
    print(text, file=handle)

def std_file_close(handle: int):
    handle.close()
"""
