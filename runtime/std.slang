
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



pub enum Key:
	KEY_NONE
	KEY_0
	KEY_1
	KEY_2
	KEY_3
	KEY_4
	KEY_5
	KEY_6
	KEY_7
	KEY_8
	KEY_9
	KEY_A
	KEY_B
	KEY_C
	KEY_D
	KEY_E
	KEY_F
	KEY_G
	KEY_H
	KEY_I
	KEY_J
	KEY_K
	KEY_L
	KEY_M
	KEY_N
	KEY_O
	KEY_P
	KEY_Q
	KEY_R
	KEY_S
	KEY_T
	KEY_U
	KEY_V
	KEY_W
	KEY_X
	KEY_Y
	KEY_Z
	KEY_UP
	KEY_DOWN
	KEY_LEFT
	KEY_RIGHT
	KEY_SPACE
	KEY_ESCAPE
	KEY_MOUSE_LEFT
	KEY_MOUSE_MIDDLE
	KEY_MOUSE_RIGHT
	KEY_MOUSE_FORWARD
	KEY_MOUSE_BACK
	KEY_SHIFT
	KEY_CONTROL
	KEY_WIN
	KEY_ALT
	KEY_APP_QUIT
	KEY_COUNT

extern "slangrt" fn sdl_init(title: str, width: int, height: int)
extern "slangrt" fn sdl_poll()
extern "slangrt" fn sdl_input_down(key: Key) -> bool
extern "slangrt" fn sdl_input_click(key: Key) -> bool
extern "slangrt" fn sdl_draw(width: int, height: int, pixels: [uint8])
extern "slangrt" fn sdl_sync(interval: float)
extern "slangrt" fn sdl_quit()
