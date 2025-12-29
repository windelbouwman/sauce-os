""" A slang-lang REPL!
"""

from std import print, read_line, get_n_args, get_arg
from logging import log_info, log_debug, set_log_level
from basepass import IdGen
from location import location_default
from parsing import parse_statement_from_text, ParseError
from namebinding import bind_names_expression
from typechecking import type_check_expression
from ir_gen import gen_expression_bytecode
from optiontype import Option
import bc
from errors import CompilationError, display_error, new_single_error
import ast
import vm
from vm import VirtualMachine, eval_code, value_to_string


pub fn main() -> int:
	var verbosity = 1
	let n = get_n_args()
	var i = 0
	while i < n:
		let argument = get_arg(arg: i)
		if argument == "-v":
			verbosity += 1
		else:
			print("Unknown argument {argument}")
			return 1
		i += 1

	print("Welcome to the slang-lang REPL!")
	set_log_level(level: verbosity)
	let r = Repl()
	loop:
		let line = read_line(prompt: "~~~> ")
		r.eval(line)
	0


class Repl:
	var id_gen: IdGen = IdGen()
	var typectx: ast.TypeContext = ast.make_typectx()
	var m_vm: VirtualMachine = VirtualMachine()

	pub fn eval(line: str):
		try:
			log_info("Parsing [{line}]")
			let statement = parse_line(typectx, line, id_gen)
			case statement.kind:
				Expr(expression):
					let x = eval_expression(expression)
					print("Computed result: {value_to_string(x)}")
			else:
				print_statement_ast(statement)
				print("Unsupported statement: {statement}")

		except (error: CompilationError):
			display_error(error)
			#for error2 in error.errors:
			#    print_error_line(line, location: error2.location, message: error2.message)

	fn eval_expression(expression: ast.Expression) -> vm.Value except CompilationError:
		# print_expression_ast(expression)
		bind_names_expression(expression)
		log_debug("Type checking")
		type_check_expression(typectx, expression)
		print_expression_ast(expression)
		log_debug("Creating bytecode")
		let code = gen_expression_bytecode(expression)
		bc.print_bc_instructions(instructions: code)
		log_debug("Executing")
		let x = eval_code(vm: m_vm, code)
		return x

fn parse_line(typectx: ast.TypeContext, line: str, id_gen: IdGen) -> ast.Statement except CompilationError:
	var statement = ast.pass_statement(location: location_default())
	try:
		statement = parse_statement_from_text(source: line, id_gen, typectx)
	except (err: ParseError):
		raise new_single_error(filename: Option.None(), location: err.location, message: err.message)
	statement

fn print_statement_ast(statement: ast.Statement):
	let visitor = ast.new_print_visitor(printer: ast.AstPrinter())
	ast.visit_statement(visitor, statement)

fn print_expression_ast(expression: ast.Expression):
	let visitor = ast.new_print_visitor(printer: ast.AstPrinter())
	ast.visit_expression(visitor, expression)
