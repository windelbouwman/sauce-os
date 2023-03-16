
from location import Location
from std import int_to_str

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

    # Literals:
    Float(float)
    Integer(int)
    String(str)

    # Punctuation:
    Colon
    Comma
    Dot

    # White-space:
    Space(int)
    NewLine

fn to_string(tok: Token) -> str:
    # """ Convert token to txt """
    let txt = "?"
    case tok.kind:
        Identifier(x):
            txt = "ID(" + x + ")"
        String(a):
            txt = "STRING(" + a + ")"
        Colon:
            txt = "COLON"
    return "row=" + int_to_str(tok.location.row) + txt
