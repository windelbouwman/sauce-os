"""
Code formatter.

Strategy: use the lexer to create tokens, and edit this token stream.
"""

import std
from std import print
from listtype import List
from utils import panic
from logging import log_info, log_debug, set_log_level
from fs import Path, new_path
from lexer import Lexer
from strlib import str_repeat, split_lines
from diff import diff_lines
from token import token_to_string, Token

pub fn main() -> int:
	let arguments = parse_arguments()
	set_log_level(level: 1)

	if arguments.sources.is_empty():
		print_help()
		return 0

	for source_path in arguments.sources:
		format_source(source_path, arguments)
	0

struct Arguments:
	check: bool
	inplace: bool
	sources: List[Path]

fn parse_arguments() -> Arguments:
	""" Process command line arguments """
	let n = std.get_n_args()
	let sources: List[Path] = List()
	var check = true
	var inplace = false
	var i = 0
	while i < n:
		let arg = std.get_arg(arg: i)
		if arg == "-i" or arg == "--in-place":
			inplace = true
		else:
			let path = new_path(filename: arg)
			sources.append(path)
		i += 1
	Arguments:
		check
		inplace
		sources

fn format_source(source_path: Path, arguments: Arguments):
	""" Format a single source file """
	log_debug("formatting {source_path} ...")
	let tokens: List[Token] = List()
	try:
		read_tokens(path: source_path, tokens)
	except (message: str):
		print(message)
		print("ERR")
		return
	let out = Gen()
	spitout(tokens, out)
	let original_lines = source_path.read_lines()
	let formatted_lines = out.get_lines()
	if xdiff(a: original_lines, b: formatted_lines) == 0:
		log_info("No formatting required for {source_path}")
	else:
		if arguments.inplace:
			log_info("Writing formatted lines to {source_path}")
			source_path.write_lines(formatted_lines)
		else:
			log_info("Would re-format {source_path}")

fn xdiff(a: List[str], b: List[str]) -> int:
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

fn spitout(tokens: List[Token], out: Gen):
	var in_string = false
	var bracket_depth = 0
	for token in tokens:
		case token.kind:
			Identifier(id): out.separated(id)

			KwAnd: out.spaced("and")
			KwBreak: out.tight("break")
			KwCase: out.spaced("case")
			KwClass: out.separated("class")
			KwContinue: out.tight("continue")
			KwElse: out.separated("else")
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
			KwNot: out.spaced("not")
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
				out.separated(raw_text if in_string else "'{raw_text}'")
			Bool(value): out.separated("true" if value else "false")

			StringStart:
				out.pre_separated("\"")
				in_string = true
			StringContent(value): out.tight(value)
			StringEnd:
				in_string = false
				out.post_separated("\"")
			DocString(lines): format_docstring(out, lines)

			Colon:
				if bracket_depth == 0:
					out.post_spaced(":")
				else:
					out.spaced(":")
			Comma: out.post_spaced(",")
			Dot: out.tight(".")
			Arrow: out.spaced("->")
			Question: out.tight("?")
			ParenthesisOpen: out.tight("(")
			ParenthesisClose: out.tight(")")
			BracketOpen:
				out.tight("[")
				bracket_depth += 1
			BracketClose:
				out.tight("]")
				bracket_depth -= 1
			BraceOpen: out.tight("\{")
			BraceClose: out.tight("}")

			Plus: out.spaced("+")
			Minus: out.spaced("-")
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
			Eof:
				pass
			None:
				pass
			Error(message):
				panic("Error: {message}")
	out.flush()

fn format_docstring(out: Gen, lines: List[str]):
	let triple = "\"\"\""
	let n = lines.len()
	if n == 1:
		out.tight(triple + lines.get(index: 0) + triple)
	elif n > 1:
		var i = 0
		for line in lines:
			if i == 0:
				out.append(triple + line)
			elif i == n - 1:
				out.emit(line + triple)
			else:
				out.raw_line(line)
			i += 1

class Gen:
	var m_lines: List[str] = List()
	var m_line: str = ""
	var m_indentation: int = 0
	var m_need_space: bool = false
	var m_needs_separator: bool = false

	pub fn separated(text?: str):
		if m_needs_separator:
			m_need_space = true
		append(text)
		m_needs_separator = true

	pub fn pre_separated(text?: str):
		if m_needs_separator:
			m_need_space = true
		append(text)
		m_needs_separator = false

	pub fn post_separated(text?: str):
		append(text)
		m_needs_separator = true

	pub fn spaced(text?: str):
		m_need_space = true
		append(text)
		m_need_space = true
		m_needs_separator = false

	pub fn post_spaced(text?: str):
		append(text)
		m_need_space = true
		m_needs_separator = false

	pub fn tight(text?: str):
		append(text)
		m_needs_separator = false

	pub fn indent():
		m_indentation += 1

	pub fn dedent():
		m_indentation -= 1

	pub fn raw_line(line?: str):
		flush()
		emit(line)
		newline()

	pub fn flush():
		if std.str_len(text: m_line) > 0:
			newline()

	pub fn append(text?: str):
		let at_bol = (std.str_len(text: m_line) == 0)
		if at_bol and (m_indentation > 0):
			emit(str_repeat(text: "\t", count: m_indentation))
		elif not at_bol and m_need_space:
			m_need_space = false
			emit(" ")
		emit(text)

	pub fn emit(text?: str):
		m_line = m_line + text

	pub fn newline():
		m_lines.append(m_line)
		m_line = ""
		m_need_space = false
		m_needs_separator = false

	pub fn get_lines() -> List[str]:
		""" Retrieve formatted lines """
		m_lines

fn print_help():
	print("Code formatter")
	print("")
	print("Usage:")
	print("format source-code-file")
