
from token import Token, TokenKind, new_token
from location import Location, new_location

struct Lexer:
    indent_level: int
    # Syntax for the list/vector type:
    # backlog: List<Token>
    # backlog: list[Token]
    # backlog: list[Token]
    at_bol: bool
    spaces: int

fn lexer_new() -> Lexer:
    let lexer = Lexer:
        indent_level: 0
        at_bol: True
        spaces: 0
    return lexer


fn next_token(lexer: Lexer) -> Token:
    # let kind = TokenKind::NewLine()
    let kind = TokenKind::String("foobar")

    let location = new_location(1, 1)
    return new_token(kind, location)

fn detect_indentations(lexer: Lexer) -> Token:
    let tok = next_token(lexer)
    if tok.location.row == 1:  # "fu":
        pass
    else:
        # return tok
        pass
    return tok

