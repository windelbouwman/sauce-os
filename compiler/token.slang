
from location import Location
from std import int_to_str
import std

fn new_token(kind: TokenKind, location: Location) -> Token:
    let tok = Token:
        kind: kind
        location: location

    return tok

struct Token:
    location: Location
    kind: TokenKind

enum TokenKind:
    Identifier(str)

    # Keywords:
    KwImport
    KwFn
    KwPass
    KwBreak
    KwContinue
    KwIf
    KwElse
    KwLoop
    KwWhile
    KwReturn
    KwStruct
    KwEnum
    KwLet

    # Literals:
    Float(float)
    Integer(int)
    String(str)

    # Punctuation:
    Colon
    Comma
    Dot
    Arrow
    BraceOpen
    BraceClose

    # White-space:
    Space(int)
    NewLine
    Comment(str)
    Indent
    Dedent

    Eof
    Error

fn token_to_string(tok: Token) -> str:
    # """ Convert token to txt """
    let txt = "?"
    case tok.kind:
        KwImport:
            txt = "IMPORT"
        KwFn:
            txt = "FN"
        Identifier(x):
            txt = "ID({x})"
        String(a):
            txt = "STRING({a})"
        Integer(v):
            txt = "INT({v})"
        Space(v):
            txt = "SPACE({v})"
        Comment(a):
            txt = "COMMENT({a})"
        NewLine:
            txt = "NEWLINE"
        Indent:
            txt = "INDENT"
        Dedent:
            txt = "DEDENT"
        Colon:
            txt = "COLON"
        Arrow:
            txt = "ARROW"
        Comma:
            txt = "COMMA"
        Dot:
            txt = "DOT"
        BraceOpen:
            txt = "BRACE_OPEN"
        BraceClose:
            txt = "BRACE_CLOSE"
        Error:
            txt = "LEX-ERROR"
    else:
        txt = "???"
    return "row={tok.location.row}:{tok.location.column} {txt}"
