
from std import print, read_file, str_get, str_len
from listtype import List, list1
from optiontype import Option
from strlib import split_lines, str_repeat, str_pad_left
from location import Location, Position, get_begin, get_end, offset_to_position

pub struct CompilationError:
	errors: List[SingleCompilationError]

enum Severity:
	Error
	Warning

pub struct SingleCompilationError:
	filename: Option[str]
	severity: Severity
	location: Location
	message: str

pub class ErrorCollector:
	var m_messages: List[SingleCompilationError] = List()
	var m_filename: Option[str] = Option.None()

	pub fn enter_file(filename: Option[str]):
		m_filename = filename

	pub fn leave_file():
		m_filename = Option.None()

	pub fn make_error(location: Location, message: str) -> SingleCompilationError:
		new_error(filename: m_filename, location, message)

	pub fn add_error(location: Location, message: str):
		append(new_error(filename: m_filename, location, message))

	pub fn add_warning(location: Location, message: str):
		append(new_warning(filename: m_filename, location, message))

	pub fn append(error?: SingleCompilationError):
		m_messages.append(error)

	pub fn render_or_raise() except CompilationError:
		let real_errors: List[SingleCompilationError] = List()
		let real_warnings: List[SingleCompilationError] = List()
		for err in m_messages:
			case err.severity:
				Error:
					real_errors.append(err)
				Warning:
					real_warnings.append(err)

		if not real_warnings.is_empty():
			print_errors(errors: real_warnings)

		if not real_errors.is_empty():
			raise new_errors(errors: real_errors)

pub fn new_error(filename: Option[str], location: Location, message: str) -> SingleCompilationError:
	SingleCompilationError(filename, severity: Severity.Error(), location, message)

pub fn new_warning(filename: Option[str], location: Location, message: str) -> SingleCompilationError:
	SingleCompilationError(filename, severity: Severity.Warning(), location, message)

pub fn new_single_error(filename: Option[str], location: Location, message: str) -> CompilationError:
	let errors = list1(new_error(filename, location, message))
	CompilationError(errors)

pub fn new_error_with_filename(filename: str, location: Location, message: str) -> CompilationError:
	new_single_error(filename: Option.Some(filename), location, message)

pub fn new_errors(errors: List[SingleCompilationError]) -> CompilationError:
	CompilationError(errors)

pub fn display_error(error: CompilationError):
	print_errors(errors: error.errors)

pub fn print_errors(errors: List[SingleCompilationError]):
	for message in errors:
		render_message(message)

fn render_message(message: SingleCompilationError):
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
	case message.filename:
		Some(filename):
			print_error(label, filename, message)
		None:
			print("{label}: {message.message}")

fn print_error(label: str, filename: str, message: SingleCompilationError):
	let code = read_file(filename)
	let begin = offset_to_position(offset: get_begin(message.location), code)
	let end = offset_to_position(offset: get_end(message.location), code)
	print("{filename}:{begin.row}.{begin.column}-{end.row}.{end.column+1}: {label} {message.message}")
	print("     +---------------[ {filename} ]-----------------")
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
