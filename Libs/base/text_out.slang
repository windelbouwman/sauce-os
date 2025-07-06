
from std import print
from std import file_writeln, file_open, file_close
from strlib import str_repeat
from optiontype import Option

pub fn new_text_out(filename: Option[str]) -> TextOut:
	let m_out = case filename:
		Some(filename):
			# See also: 'text_gen.slang'
			# TODO: de-duplicate by means of dynamic dispatch/traits
			let handle = file_open(filename, mode: "w")
			TextOutType.File(handle)
		None:
			TextOutType.Console()
	TextOut(m_out)

pub fn new_console_text_out() -> TextOut:
	TextOut(m_out: TextOutType.Console())

enum TextOutType:
	Console
	File(handle: int)

pub class TextOut:
	var m_out: TextOutType
	var indentation: int = 0

	pub fn indent():
		indentation += 1

	pub fn dedent():
		indentation -= 1

	pub fn emit(text?: str):
		let indent_spaces = str_repeat(text: "   ", count: indentation)
		let line = indent_spaces + text
		case m_out:
			Console:
				print(line)
			File(handle):
				file_writeln(handle, line)

	pub fn end():
		case m_out:
			Console:
				pass
			File(handle):
				file_close(handle)

# struct FileTextOutput:
# 	a: int

# struct ConsoleTextOutput:
# 	b: int

# impl TextOut for FileTextOutput:
# 	fn emit(text?: str):
# 		# writeln
# 		pass

# impl TextOut for ConsoleTextOutput:
# 	fn emit(text?: str):
# 		print(text)
