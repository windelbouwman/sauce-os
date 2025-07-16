
from std import print, read_file, str_get, str_len
from listtype import List
from optiontype import Option
from strlib import split_lines, str_repeat, str_pad_left, is_lf
from location import Location, Position

pub struct CompilationError:
	filename: Option[str]
	errors: List[SingleCompilationError]

enum Severity:
	Error
	Warning

pub struct SingleCompilationError:
	severity: Severity
	location: Location
	message: str

pub fn new_error(location: Location, message: str) -> SingleCompilationError:
	SingleCompilationError(severity: Severity.Error(), location, message)

pub fn new_warning(location: Location, message: str) -> SingleCompilationError:
	SingleCompilationError(severity: Severity.Warning(), location, message)

pub fn new_errors(filename: Option[str], errors: List[SingleCompilationError]) -> CompilationError:
	CompilationError(filename, errors)

pub fn display_error(error: CompilationError):
	print_errors(filename: error.filename, errors: error.errors)

pub fn print_errors(filename: Option[str], errors: List[SingleCompilationError]):
	for message in errors:
		render_message(filename, message)

fn render_message(filename: Option[str], message: SingleCompilationError):
	# reset = \033[0m
	# red = \033[31m
	# green = \033[32m
	# yellow = \033[33m
	# blue = \033[34m
	# magenta = \033[35m
	# print("\033[33mwarning\033[0m: {message}")
	let label = case message.severity:
		Error:
			"\033[31merror\033[0m"
		Warning:
			"\033[33mwarning\033[0m"
	# let one_line = false
	case filename:
		Some(filename):
			# if one_line:
			print_error_one_line(label, filename, message)
			# else:
			print_error(label, filename, message)
		None:
			print("{label}: {message.message}")

fn offset_to_position(offset: int, code: str) -> Position:
	""" Calculate row and column from offset in string."""
	var index = 0
	var row = 1
	var column = 1
	while index < offset:
		let c = str_get(text: code, index)
		if is_lf(c):
			row += 1
			column = 1
		else:
			column += 1
		index += 1
	Position(row, column)

fn print_error_one_line(label: str, filename: str, message: SingleCompilationError):
	let code = read_file(filename)
	let begin = offset_to_position(offset: message.location.begin, code)
	print("{filename}:{begin.row}.{begin.column}: {label} {message.message}")

fn print_error(label: str, filename: str, message: SingleCompilationError):
	print("     +---------------[ {filename} ]-----------------")
	let code = read_file(filename)
	let begin = offset_to_position(offset: message.location.begin, code)
	let end = offset_to_position(offset: message.location.end, code)
	let target_row = begin.row
	let nr_context_rows = 4
	var row = 1
	for line in split_lines(text: code):
		if target_row - nr_context_rows <= row and row <= target_row + nr_context_rows:
			let row_text = str_pad_left(text: "{row}", length: 5, fill: " ")
			print("{row_text}|\t{line}")
			let pre_text = "     |\t"

			if row == target_row:
				let n_tabs = count_leading_tabs(text: line)
				let indent = pre_text + str_repeat(text: "\t", count: n_tabs) + str_repeat(text: " ", count: begin.column - 1 - n_tabs)
				var lexeme_width = 1
				if end.column > begin.column:
					lexeme_width = end.column - begin.column + 1
				let pointer = str_repeat(text: "^", count: lexeme_width)
				let indent2 = indent + str_repeat(text: " ", count: lexeme_width / 2)
				print("{indent}{pointer}")
				print("{indent2}|")
				print("{indent2}+-----< {label}: {message.message}")
				print("{pre_text}")

		row += 1
	print("     +----------------------------------------------")
	print("")

fn count_leading_tabs(text: str) -> int:
	var index = 0
	let n = str_len(text)
	while index < n:
		if str_get(text, index) == '\t':
			index += 1
		else:
			break
	index

# fn print_error_line(line: str, location: Location, message: str):
#     print(" {line}")
#     let indent = str_repeat(text: " ", count: location.begin.column)
#     let lexeme_width = 1
#     if location.end.column > location.begin.column:
#         lexeme_width = location.end.column - location.begin.column + 1
#     let pointer = str_repeat(text: "^", count: lexeme_width)
#     let indent2 = indent + str_repeat(text: " ", count: lexeme_width / 2)
#     print("{indent}{pointer}")
#     print("{indent2}|")
#     print("{indent2}+-----< {message}")
