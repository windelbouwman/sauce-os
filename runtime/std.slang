
# Header file for std runtime module

extern fn ord(value: char) -> int
extern fn chr(value: int) -> char

extern fn float_to_str(value: float) -> str
extern fn float_to_str2(value: float, digits: int) -> str
extern fn str_to_float(value: str) -> float

# extern fn int_to_str(value: int) -> str
extern fn str_to_int(value: str) -> int

extern fn str_len(value: str) -> int
extern fn str_get(value: str, index: int) -> char
extern fn str_slice(value: str, begin: int, end: int) -> str

extern fn print(message: str)
# '?' indicates that function does not return.
# TODO: improve syntax for noreturn functions
extern fn exit(code: int) ?

extern fn read_file(filename: str) -> str
extern fn file_open(filename: str) -> int
extern fn file_writeln(handle: int, line: str)
extern fn file_close(handle: int)

extern fn get_n_args() -> int
extern fn get_arg(arg: int) -> str

