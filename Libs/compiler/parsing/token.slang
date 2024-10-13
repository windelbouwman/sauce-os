
from location import Location, location_to_string
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
    KwExtern
    KwFn
    KwFor
    KwFrom
    KwIf
    KwImport
    KwIn
    KwLet
    KwLoop
    KwMacro
    KwNot
    KwOr
    KwPass
    KwPub
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
    Char(value: char)
    Bool(value: bool)

    StringStart
    StringContent(value: str)
    StringEnd

    # Punctuation:
    Colon
    Comma
    Dot
    Arrow
    Question
    ParenthesisOpen
    ParenthesisClose
    BracketOpen
    BracketClose
    BraceOpen
    BraceClose

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
    ShiftRight
    ShiftLeft
    BitOr
    BitAnd
    BitXor
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
    None
    Error(message: str)

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
        KwExtern:
            txt = "EXTERN"
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
        KwMacro:
            txt = "MACRO"
        KwNot:
            txt = "NOT"
        KwOr:
            txt = "OR"
        KwPass:
            txt = "PASS"
        KwPub:
            txt = "PUB"
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
        StringStart:
            txt = "STRING_START"
        StringContent(content):
            txt = "STRING_CONTENT({content})"
        StringEnd:
            txt = "STRING_END"
        Char(value):
            txt = "CHAR({value})"
        Integer(value):
            txt = "INT({value})"
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
        ShiftRight:
            txt = "shr"
        ShiftLeft:
            txt = "shl"
        BitOr:
            txt = "bitor"
        BitAnd:
            txt = "bitand"
        BitXor:
            txt = "bitxor"
        ParenthesisOpen:
            txt = "("
        ParenthesisClose:
            txt = ")"
        BracketOpen:
            txt = "["
        BracketClose:
            txt = "]"
        BraceOpen:
            txt = "\{"
        BraceClose:
            txt = "}"
        Error(message):
            txt = "LEX-ERROR({message})"
        Eof:
            txt = "EOF"
        None:
            txt = "None"

    return txt
