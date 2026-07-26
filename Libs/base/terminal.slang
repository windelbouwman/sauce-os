module base.terminal
"""Terminal colors"""

# reset = \033[0m
# red = \033[31m
# green = \033[32m
# yellow = \033[33m
# blue = \033[34m
# magenta = \033[35m

pub enum Color:
	Black
	Red
	Green
	Yellow
	Blue
	Magenta
	Cyan
	White

pub fn colored_text(text: str, color: Color) -> str:
	let code = 30 + get_color_code(color)
	"{sgr(code)}{text}{sgr(0)}"

fn sgr(code?: int) -> str:
	"\033[{code}m"

fn get_color_code(color: Color) -> int:
	case color:
		Black: 0
		Red: 1
		Green: 2
		Yellow: 3
		Blue: 4
		Magenta: 5
		Cyan: 6
		White: 7
