
import ast
import std
import lexer
from datatypes import List

fn parse_source(filename: str) -> ast.Module:
    let source = std::read_file(filename)

    std::print("Source-code")
    std::print("===============")
    std.print(source)
    std::print("===============")

    let lex = lexer::lexer_new()
    let tok = lexer::detect_indentations(lex)
    std::print("tok at {tok.location.row}")

    let definitions = List()
    let program = ast::Module:
        name: "FUU"
        definitions: definitions
    
    return program
