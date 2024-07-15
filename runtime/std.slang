
# Header file for std runtime module

extern "runtime" fn ord(value?: char) -> int
extern "runtime" fn chr(value?: int) -> char

extern "runtime" fn float_to_str(value?: float) -> str
extern "runtime" fn float_to_str2(value: float, digits: int) -> str
extern "runtime" fn str_to_float(value?: str) -> float

# extern "runtime" fn int_to_str(value: int) -> str
extern "runtime" fn str_to_int(value?: str) -> int

extern "runtime" fn str_len(text: str) -> int
extern "runtime" fn str_get(text: str, index: int) -> char
extern "runtime" fn str_slice(text: str, begin: int, end: int) -> str

extern "runtime" fn print(message?: str)
# '?' indicates that function does not return.
# TODO: improve syntax for noreturn functions
extern "runtime" fn exit(code: int) ?

extern "runtime" fn read_file(filename: str) -> str
extern "runtime" fn file_open(filename: str, mode: str) -> int
extern "runtime" fn file_writeln(handle: int, line: str)
extern "runtime" fn file_read_n_bytes(handle: int, buffer: [uint8], bufsize: int) -> int
extern "runtime" fn file_close(handle: int)

extern "runtime" fn get_n_args() -> int
extern "runtime" fn get_arg(arg: int) -> str

# fn read_binary
