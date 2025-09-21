# Runtime functions implemented in python.

import sys
import os
import time


def std_get_n_args() -> int:
    return len(sys.argv) - 1


def std_get_arg(index) -> str:
    return sys.argv[index + 1]


def std_read_file(filename: str) -> str:
    with open(filename, "r") as f:
        return f.read()


def std_exit(code: int):
    raise RuntimeError(f"EXIT with code: {code}")


def std_get_path_separator() -> str:
    return os.sep


std_print = print
std_read_line = input
rt_int_to_str = str


def std_float_to_str(value: float) -> str:
    return f"{value:f}"


def std_float_to_str2(value: float, digits: int) -> str:
    return f"{value:.{digits}f}"


std_str_len = len
rt_str_len = len
std_ord = ord
std_chr = chr

rt_char_to_str = str


def std_str_get(s, i):
    return s[i]


def rt_str_get(s, i):
    return s[i]


def std_str_slice(s, b, e):
    return s[b:e]


def rt_str_concat(a, b):
    return a + b


def rt_str_compare(a, b):
    return a == b


def std_file_open(filename: str, mode: str) -> int:
    return open(filename, mode)


def std_file_get_stdin() -> int:
    raise NotImplementedError("std_get_stdin")


def std_file_get_stdout() -> int:
    return sys.stdout


def std_file_readln(handle: int) -> str:
    raise NotImplementedError("std_file_readln")


def std_file_write(handle: int, text: str):
    print(text, file=handle, end="")


def std_file_writeln(handle: int, text: str):
    print(text, file=handle)


def std_file_read_n_bytes(handle: int, buf: list, bufsize: int) -> int:
    data = handle.read(bufsize)
    for i, b in enumerate(data):
        buf[i] = b
    return len(data)


def std_file_write_n_bytes(handle: int, buf: list, bufsize: int) -> int:
    data = bytes(buf[:bufsize])
    handle.write(data)
    return len(data)


def std_file_seek(handle: int, pos: int):
    handle.seek(pos)


def std_file_tell(handle: int) -> int:
    return handle.tell()


def std_file_close(handle: int):
    handle.close()


def std_get_time() -> int:
    time.time_ns()
