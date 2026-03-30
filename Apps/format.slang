module main
"""Code formatter.

Strategy: use the lexer to create tokens, and edit this token stream.
"""

import std
from std import print
from base.listtype import List
from base.vectype import Vector, new_vector
from base.utils import panic
from base.logging import log_info, log_debug, log_error, set_log_level
from base.fs import Path, new_path
from compiler.lexer import Lexer
from base.strlib import str_repeat, split_lines, StringBuilder
from base.diff import diff_lines
from compiler.token import token_to_string, Token

pub fn main() -> int:
	let arguments = parse_arguments()
	set_log_level(level: 1)

	if arguments.show_help or arguments.sources.is_empty():
		print_help()
		return 0

	let status = Status(untouched_files: 0, formatted_files: 0, invalid_files: 0)
	for source_path in arguments.sources:
		format_source(source_path, arguments, status)

	if status.invalid_files > 0:
		print("{status.invalid_files} invalid files")
		return 1

	if arguments.check:
		if status.formatted_files > 0:
			print("Would need to format {status.formatted_files}/{arguments.sources.len()} files.")
			1
		else:
			print("All {status.untouched_files} of the {arguments.sources.len()} files are well formatted!")
			0
	else:
		print("Formatted: {status.formatted_files} of the {arguments.sources.len()} files. Untouched: {status.untouched_files} of the {arguments.sources.len()} files.")
		0

struct Arguments:
	show_help: bool
	check: bool
	inplace: bool
	sources: List[Path]

struct Status:
	untouched_files: int
	formatted_files: int
	invalid_files: int

fn parse_arguments() -> Arguments:
	"""Process command line arguments"""
	let n = std.get_n_args()
	let sources: List[Path] = List()
	var show_help = false
	var check = false
	var inplace = false
	var i = 0
	while i < n:
		let arg = std.get_arg(arg: i)
		if arg == "-i" or arg == "--in-place":
			inplace = true
		elif arg == "--check":
			check = true
		elif arg == "-h" or arg == "--help":
			show_help = true
		else:
			let path = new_path(filename: arg)
			sources.append(path)
		i += 1
	Arguments(show_help, check, inplace, sources)

fn format_source(source_path: Path, arguments: Arguments, status: Status):
	"""Format a single source file"""
	log_debug("formatting {source_path} ...")
	let tokens: List[Token] = List()
	try:
		read_tokens(path: source_path, tokens)
	except (message: str):
		log_error("Cannot read {source_path}: {message}")
		status.invalid_files += 1
		return
	let formatted_lines = format_tokens(tokens)
	let original_lines = source_path.read_lines()
	if run_line_diff(original_lines, formatted_lines) == 0:
		log_info("No formatting required for {source_path}")
		status.untouched_files += 1
	else:
		if arguments.inplace:
			log_info("Writing formatted lines to {source_path}")
			source_path.write_lines(formatted_lines)
		else:
			log_info("Would re-format {source_path}")
		status.formatted_files += 1

fn run_line_diff(a?: Vector[str], b?: Vector[str]) -> int:
	var n_diffs = 0
	for edit in diff_lines(a, b):
		case edit:
			Equal(pos1, pos2, value):
				pass
			Delete(pos, value):
				print("{pos}..: -- {value}")
				n_diffs += 1
			Insert(pos1, pos2, value):
				print("{pos1}..{pos2}: ++ {value}")
				n_diffs += 1
	n_diffs

fn read_tokens(path: Path, tokens: List[Token]) except str:
	let source = path.read_text()
	let lex = Lexer()
	lex.init(source)
	lex.keep_comments()

	loop:
		let token = lex.next_token()
		case token.kind:
			Eof:
				break
			Error(message):
				raise message
		else:
			tokens.append(token)

fn format_tokens(tokens: List[Token]) -> Vector[str]:
	"""Format a list of tokens into text lines."""
	let out = Gen()
	var in_string = false
	var bracket_depth = 0
	var parenthesis_depth = 0
	var was_end_expr = false
	var in_type = false
	var in_if = false
	for token in tokens:
		case token.kind:
			Identifier(id): out.separated(id)

			KwAnd: out.spaced("and")
			KwBreak: out.text("break")
			KwCase: out.spaced("case")
			KwClass: out.separated("class")
			KwContinue: out.text("continue")
			KwElse:
				if in_if:
					out.spaced("else")
				else:
					out.separated("else")
			KwElif: out.spaced("elif")
			KwEnum: out.spaced("enum")
			KwExcept: out.spaced("except")
			KwExtern: out.spaced("extern")
			KwFn: out.separated("fn")
			KwFor: out.spaced("for")
			KwFrom: out.spaced("from")
			KwIf: out.spaced("if")
			KwImport: out.spaced("import")
			KwImpl: out.separated("impl")
			KwIn: out.spaced("in")
			KwInterface: out.spaced("interface")
			KwLet: out.spaced("let")
			KwLoop: out.separated("loop")
			KwMacro: out.separated("macro")
			KwModule: out.separated("module")
			KwNot:
				out.separator()
				out.text("not")
				out.space()
			KwOr: out.spaced("or")
			KwPass: out.separated("pass")
			KwPub: out.separated("pub")
			KwRaise: out.spaced("raise")
			KwReturn: out.spaced("return")
			KwStruct: out.spaced("struct")
			KwSwitch: out.spaced("switch")
			KwTry: out.separated("try")
			KwType: out.separated("type")
			KwVar: out.separated("var")
			KwWhile: out.spaced("while")
			KwUnreachable: out.separated("unreachable")
			KwBox: out.separated("box")
			KwUnbox: out.separated("unbox")
			KwNull: out.separated("null")

			Float(value, raw_text): out.separated(raw_text)
			Integer(value, raw_text): out.separated(raw_text)
			Char(value): out.separated("'{value}'")
			EscapedChar(value, mode, raw_text):
				if in_string:
					out.text(raw_text)
				else:
					out.separated("'{raw_text}'")
			Bool(value): out.separated("true" if value else "false")

			StringStart:
				out.separator()
				out.text("\"")
				in_string = true
			StringContent(value): out.text(value)
			StringEnd:
				in_string = false
				out.text("\"")
				out.separator()
			DocString(lines): format_docstring(out, lines)

			Colon:
				if bracket_depth > 0:
					out.space()
				out.text(":")
				out.space()
			Comma:
				out.text(",")
				if not (in_type and bracket_depth > 0):
					out.space()
			Dot: out.text(".")
			Arrow: out.spaced("->")
			Question: out.text("?")
			ParenthesisOpen: out.text("(")
			ParenthesisClose: out.text(")")
			BracketOpen: out.text("[")
			BracketClose: out.text("]")
			BraceOpen: out.text("\{")
			BraceClose: out.text("}")

			Plus: out.spaced("+")
			Minus:
				if was_end_expr:
					out.spaced("-")
				else:
					out.text("-")
			Slash: out.spaced("/")
			Percent: out.spaced("%")
			Asterix: out.spaced("*")
			Less: out.spaced("<")
			LessEquals: out.spaced("<=")
			Greater: out.spaced(">")
			GreaterEquals: out.spaced(">=")
			Equals: out.spaced("=")
			EqualsEquals: out.spaced("==")
			ShiftRight: out.spaced(">>")
			ShiftLeft: out.spaced("<<")
			BitOr: out.spaced("|")
			BitAnd: out.spaced("&")
			BitXor: out.spaced("^")
			NotEquals: out.spaced("!=")
			PlusEquals: out.spaced("+=")
			MinusEquals: out.spaced("-=")
			AsterixEquals: out.spaced("*=")
			SlashEquals: out.spaced("/=")

			Space(amount): panic("Spaces not supported")
			Tab(amount): panic("Tabs not supported")

			NewLine: out.newline()
			Comment(comment):
				out.emit("  " + comment)
				out.newline()
			TabbedComment(tabs, comment):
				let tab_text = str_repeat(text: "\t", count: tabs)
				out.raw_line(tab_text + comment)
			Indent: out.indent()
			Dedent: out.dedent()
			Eof: panic("EOF-token not supported")
			None: panic("None-token not supported")
			Error(message): panic("Error: {message}")

		# Determine if the token could be left hand side of binary expression
		case token.kind:
			Identifier(x):
				was_end_expr = true
			ParenthesisClose:
				was_end_expr = true
			Float(value, raw_text):
				was_end_expr = true
			Integer(value, raw_text):
				was_end_expr = true
		else:
			was_end_expr = false

		# Determine bracket depths
		case token.kind:
			KwFn:
				in_type = true
			KwStruct:
				in_type = true
			KwEnum:
				in_type = true
			KwClass:
				in_type = true
			KwIf:
				in_if = true
			ParenthesisOpen:
				parenthesis_depth += 1
			ParenthesisClose:
				parenthesis_depth -= 1
			BracketOpen:
				bracket_depth += 1
			BracketClose:
				bracket_depth -= 1
			Colon:
				in_type = true
			Comma:
				if bracket_depth == 0:
					in_type = false
			Equals:
				in_type = false
			Arrow:
				in_type = true
			NewLine:
				in_type = false
				in_if = false
				bracket_depth = 0
				parenthesis_depth = 0
		else:
			pass

	out.flush()
	out.get_lines()

fn format_docstring(out: Gen, lines: List[str]):
	let triple = "\"\"\""
	let n = lines.len()
	if n == 1:
		out.text(triple + lines.get(index: 0) + triple)
	elif n > 1:
		var i = 0
		for line in lines:
			if i == 0:
				out.text(triple + line)
			elif i == n - 1:
				out.raw_line(line)
				out.text(triple)
			else:
				out.raw_line(line)
			i += 1
	else:
		out.text(triple + " " + triple)

class Gen:
	var m_lines: Vector[str] = new_vector()
	var m_builder: StringBuilder = StringBuilder()
	var m_indentation: int = 0
	var m_need_space: bool = false
	var m_needs_separator: bool = false

	pub fn separated(txt?: str):
		separator()
		text(txt)
		separator()

	pub fn spaced(txt?: str):
		space()
		text(txt)
		space()

	pub fn separator():
		if m_needs_separator:
			m_need_space = true
		m_needs_separator = true

	pub fn space():
		m_need_space = true

	pub fn indent():
		m_indentation += 1

	pub fn dedent():
		m_indentation -= 1

	pub fn raw_line(line?: str):
		flush()
		emit(line)
		newline()

	pub fn flush():
		if m_builder.len() > 0:
			newline()

	pub fn text(value?: str):
		let at_bol = (m_builder.len() == 0)
		if at_bol and (m_indentation > 0):
			emit(str_repeat(text: "\t", count: m_indentation))
		elif not at_bol and m_need_space:
			m_need_space = false
			emit(" ")
		emit(value)
		m_needs_separator = false

	pub fn emit(text?: str):
		m_builder.push(text)

	pub fn newline():
		m_lines.append(m_builder.get())
		m_need_space = false
		m_needs_separator = false

	pub fn get_lines() -> Vector[str]:
		"""Retrieve formatted lines"""
		m_lines

fn print_help():
	print("Code formatter")
	print("")
	print("Usage:")
	print("$ format.exe [--check] [--in-place] file1.slang file2.slang ..")
	print("    -h --help       : Show this message")
	print("    --check         : check the formatting, to not apply")
	print("    -i --in-place   : Write formatted file")
