
# Header file for std runtime module

extern "slangrt" fn ord(value?: char) -> int
extern "slangrt" fn chr(value?: int) -> char

extern "slangrt" fn float_to_str(value?: float) -> str
extern "slangrt" fn float_to_str2(value: float, digits: int) -> str

extern "slangrt" fn str_len(text: str) -> int
extern "slangrt" fn str_get(text: str, index: int) -> char
extern "slangrt" fn str_slice(text: str, begin: int, end: int) -> str

extern "slangrt" fn print(message?: str)
extern "slangrt" fn read_line(prompt: str) -> str

extern "slangrt" fn get_path_separator() -> char

# '?' indicates that function does not return.
# TODO: improve syntax for noreturn functions
extern "slangrt" fn exit(code: int) -> unreachable

extern "slangrt" fn file_exists(filename: str) -> bool
extern "slangrt" fn read_file(filename: str) -> str
extern "slangrt" fn file_get_stdin() -> int
extern "slangrt" fn file_get_stdout() -> int
extern "slangrt" fn file_open(filename: str, mode: str) -> int
extern "slangrt" fn file_readln(handle: int) -> str
extern "slangrt" fn file_writeln(handle: int, line: str)
extern "slangrt" fn file_write(handle: int, text: str)
extern "slangrt" fn file_read_n_bytes(handle: int, buffer: [uint8], bufsize: int) -> int
extern "slangrt" fn file_write_n_bytes(handle: int, buffer: [uint8], bufsize: int) -> int
extern "slangrt" fn file_seek(handle: int, pos: int)
extern "slangrt" fn file_tell(handle: int) -> int
extern "slangrt" fn file_close(handle: int)

extern "slangrt" fn get_n_args() -> int
extern "slangrt" fn get_arg(arg: int) -> str

extern "slangrt" fn get_time() -> int

extern "slangrt" fn sdl_init(title: str, width: int, height: int)
extern "slangrt" fn sdl_poll()
extern "slangrt" fn sdl_input_quit() -> bool
extern "slangrt" fn sdl_draw(width: int, height: int, pixels: [uint8])
extern "slangrt" fn sdl_quit()
