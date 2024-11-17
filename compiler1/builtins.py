"""A set of builtin functions."""

from .location import Location, Span
from . import ast


def create_rt_module() -> ast.Module:
    modname = "rt"
    span = Span.default()
    mod = ast.Module(modname, [], [], span)
    mod.add_definition(
        ast.ExternFunction(
            modname, "int_to_str", [ast.int_type], ast.str_type, Location.default()
        ),
    )
    mod.add_definition(
        ast.ExternFunction(
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

    def std_float_to_str2(value: float, digits: int) -> str:
        return f"{value:.{digits}f}"

    return {
        "std_print": std_print,
        "std_exit": std_exit,
        "std_read_file": std_read_file,
        "rt_int_to_str": str,
        "std_float_to_str": lambda x: f"{x:f}",
        "std_float_to_str2": std_float_to_str2,
        "rt_char_to_str": str,
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
