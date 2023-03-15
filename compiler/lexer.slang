
from token import Token, TokenKind
from location import Location

struct Lexer:
    indent_level: int
    # Syntax for the list/vector type:
    # backlog: List<Token>
    # backlog: list[Token]
    # backlog: list[Token]

fn lexer_new() -> Lexer:
    let x = Lexer:
        indent_level: 0
    return x

fn detect_indentations(lexer: Lexer) -> Token:
    let tok = next_token(lexer)
    if tok.location.row == 1:  # "fu":
        pass
    else:
        # return tok
        pass
    return tok


fn next_token(lexer: Lexer) -> Token:
    # let kind = TokenKind::NewLine()
    let kind = TokenKind::String("foobar")
    let location = Location:
        row: 1
        column: 1

    # value: 
    let t = Token:
        kind: kind
        location: location

    return t