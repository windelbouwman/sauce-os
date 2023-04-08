
import ast
import std
import lexer
from token import to_string
from datatypes import List

fn parse_source(filename: str) -> ast.Module:
    let source = std::read_file(filename)

    std::print("Source-code")
    std::print("===============")
    std.print(source)
    std::print("===============")

    let lex = lexer::Lexer()
    lex.init(source)
    loop:
        case lex.next_token():
            None:
                break
            Some(tok):
                std::print(to_string(tok))

    let definitions = List()
    let program = ast::Module:
        name: "FUU"
        definitions: definitions
    
    return program
