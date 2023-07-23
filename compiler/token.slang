
from location import Location
from std import int_to_str
import std

struct Token:
    location: Location
    kind: TokenKind

enum TokenKind:
    Identifier(id: str)

    # Keywords:
    KwAnd
    KwBreak
    KwCase
    KwClass
    KwContinue
    KwElse
    KwElif
    KwEnum
    KwExcept
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
    KwRaise
    KwReturn
    KwStruct
    KwSwitch
    KwTry
    KwVar
    KwWhile

    # Literals:
    Float(value: float)
    Integer(value: int)
    String(value: str)
    Bool(value: bool)

    # Punctuation:
    Colon
    Comma
    Dot
    Arrow
    Question
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
    NotEquals
    PlusEquals
    MinusEquals

    # White-space:
    Space(amount: int)
    NewLine
    Comment(comment: str)
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
        KwExcept:
            txt = "EXCEPT"
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
        KwRaise:
            txt = "RAISE"
        KwReturn:
            txt = "RETURN"
        KwStruct:
            txt = "STRUCT"
        KwSwitch:
            txt = "SWITCH"
        KwTry:
            txt = "TRY"
        KwVar:
            txt = "VAR"
        KwWhile:
            txt = "WHILE"
        Identifier(id):
            txt = "ID({id})"
        String(a):
            txt = "STRING({a})"
        Integer(v):
            txt = "INT({v})"
        Float(v):
            txt = "FLOAT(...)"
        Bool(value):
            if value:
                txt = "BOOL(yes)"
            else:
                txt = "BOOL(no)"
        Space(amount):
            txt = "SPACE({amount})"
        Comment(comment):
            txt = "COMMENT({comment})"
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
        Question:
            txt = "QUESTION"
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
        NotEquals:
            txt = "!="
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
