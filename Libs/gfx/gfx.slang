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

extern "gfx" fn init(title: str, width: int, height: int)
extern "gfx" fn poll()
extern "gfx" fn input_down(key: Key) -> bool
extern "gfx" fn input_click(key: Key) -> bool
extern "gfx" fn draw(width: int, height: int, pixels: [uint8])
extern "gfx" fn sync(interval: float)
extern "gfx" fn quit()
