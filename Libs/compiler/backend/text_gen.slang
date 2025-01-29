
# Helper class to emit text code

from std import file_writeln, file_write, file_open, file_close, file_get_stdout
from datatypes import Option, option_is_some, option_unwrap

pub class TextGenerator:
	var m_indentation: int = 0
	var m_start_of_line: bool = true
	var use_file: bool = false
	var outf: int = 0
	pub var m_one_tab: str = "    "

	pub fn begin(output_filename: Option[str]):
		if option_is_some(output_filename):
			outf = file_open(filename: option_unwrap(output_filename), mode: "w")
			use_file = true
		else:
			outf = file_get_stdout()

	pub fn end():
		if use_file:
			file_close(handle: outf)

	pub fn indent():
		m_indentation += 1

	pub fn dedent():
		m_indentation -= 1

	pub fn emit(text?: str):
		writeln(text)

	pub fn write(text?: str):
		write_indent()
		file_write(handle: outf, text)

	pub fn writeln(text?: str):
		write_indent()
		file_writeln(handle: outf, line: text)
		m_start_of_line = true

	fn write_indent():
		if m_start_of_line:
			let i = 0
			while i < m_indentation:
				file_write(handle: outf, text: m_one_tab)
				i += 1
			m_start_of_line = false
