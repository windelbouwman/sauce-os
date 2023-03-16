
import std
import ast
import parsing

fn main() -> int:
    let filename = "main.slang"
    std::print("Compiling: {filename}")
    let program: ast::Module = parsing::parse_source(filename)
    return 0
