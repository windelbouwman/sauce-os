# Runtime functions implemented in python.

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


def std_str_slice(s, b, e):
    return s[b:e]
