
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
    KwAnd
    KwBreak
    KwCase
    KwClass
    KwContinue
    KwElse
    KwElif
    KwEnum
    KwFn
    KwFor
    KwFrom
    KwIf
    KwImport
    KwIn
    KwLet
    KwLoop
    KwNot
    KwOr
    KwPass
    KwReturn
    KwStruct
    KwSwitch
    KwVar
    KwWhile

    # Literals:
    Float(float)
    Integer(int)
    String(str)
    Bool(bool)

    # Punctuation:
    Colon
    Comma
    Dot
    Arrow
    BraceOpen
    BraceClose
    BracketOpen
    BracketClose

    Plus
    Minus
    Slash
    Asterix
    Less
    Greater
    LessEquals
    GreaterEquals
    Equals
    EqualsEquals
    PlusEquals
    MinusEquals

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
        KwAnd:
            txt = "AND"
        KwBreak:
            txt = "BREAK"
        KwCase:
            txt = "CASE"
        KwClass:
            txt = "CLASS"
        KwContinue:
            txt = "CONTINUE"
        KwElse:
            txt = "ELSE"
        KwElif:
            txt = "ELIF"
        KwEnum:
            txt = "ENUM"
        KwFn:
            txt = "FN"
        KwFor:
            txt = "FOR"
        KwFrom:
            txt = "FROM"
        KwIf:
            txt = "IF"
        KwImport:
            txt = "IMPORT"
        KwIn:
            txt = "IN"
        KwLet:
            txt = "LET"
        KwLoop:
            txt = "LOOP"
        KwNot:
            txt = "NOT"
        KwOr:
            txt = "OR"
        KwPass:
            txt = "PASS"
        KwReturn:
            txt = "RETURN"
        KwStruct:
            txt = "STRUCT"
        KwSwitch:
            txt = "SWITCH"
        KwVar:
            txt = "VAR"
        KwWhile:
            txt = "WHILE"
        Identifier(x):
            txt = "ID({x})"
        String(a):
            txt = "STRING({a})"
        Integer(v):
            txt = "INT({v})"
        Float(v):
            txt = "FLOAT(...)"
        Bool(v):
            if v:
                txt = "BOOL(yes)"
            else:
                txt = "BOOL(no)"
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
        Plus:
            txt = "+"
        Minus:
            txt = "-"
        Slash:
            txt = "/"
        Asterix:
            txt = "*"
        Equals:
            txt = "="
        EqualsEquals:
            txt = "=="
        PlusEquals:
            txt = "+="
        MinusEquals:
            txt = "-="
        Less:
            txt = "<"
        LessEquals:
            txt = "<="
        Greater:
            txt = ">"
        GreaterEquals:
            txt = ">="
        BraceOpen:
            txt = "BRACE_OPEN"
        BraceClose:
            txt = "BRACE_CLOSE"
        BracketOpen:
            txt = "["
        BracketClose:
            txt = "]"
        Error:
            txt = "LEX-ERROR"
        Eof:
            txt = "EOF"

    return "row={tok.location.row}:{tok.location.column} {txt}"
