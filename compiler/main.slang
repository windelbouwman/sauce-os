
import std
import ast
import parsing

fn main() -> int:
    let filename = "main.slang"
    std::print("Compiling: " + filename)
    let program: ast::Module = parsing::parse_source(filename)
    std::print("Parsed module: " + program.name)
    ast.print_ast(program)
    return 0
