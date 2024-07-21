
# A slang-lang REPL!

from std import print, read_line
from utils import log_info, log_debug, set_log_level
from basepass import IdGen
from parsing import parse_expr_from_text, parse_statement_from_text
from namebinding import bind_names_expression
from typechecking import type_check_expression
from ir_gen import gen_expression_bytecode
import bc
from location import Position
from errors import CompilationError, display_error
import ast
import vm
from vm import VirtualMachine, eval_code, value_to_string


fn main() -> int:
    print("Welcome to the slang-lang REPL!")
    set_log_level(level: 1)
    let r = Repl()
    loop:
        let line = read_line(prompt: "~~~> ")
        r.eval(line)
    return 0


class Repl:
    var id_gen: IdGen = IdGen()
    var m_vm: VirtualMachine = VirtualMachine()

    fn eval(line: str):
        try:
            log_info("Parsing [{line}]")
            let p1 = Position(row: 1, column: 1)
            let statement = parse_statement_from_text(source: line, id_gen, p1)
            case statement.kind:
                Expr(expression):
                    let x = eval_expression(expression)
                    print("Computed result: {value_to_string(x)}")
            else:
                print_statement_ast(statement)
                print("Unsupported statement: {ast.statement_to_string(statement)}")

        except (error: CompilationError):
            display_error(error)
    
    fn eval_expression(expression: ast.Expression) -> vm.Value except CompilationError:
        # print_expression_ast(expression)
        bind_names_expression(expression)
        log_debug("Type checking")
        type_check_expression(expression)
        print_expression_ast(expression)
        log_debug("Creating bytecode")
        let code = gen_expression_bytecode(expression)
        bc.print_bc_instructions(instructions: code)
        log_debug("Executing")
        let x = eval_code(vm: m_vm, code)
        return x

fn print_statement_ast(statement: ast.Statement):
    let visitor = ast.new_print_visitor(printer: ast.AstPrinter())
    ast.visit_statement(visitor, statement)

fn print_expression_ast(expression: ast.Expression):
    let visitor = ast.new_print_visitor(printer: ast.AstPrinter())
    ast.visit_expression(visitor, expression)
