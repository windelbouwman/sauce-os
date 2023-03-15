
from location import Location

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

    Space(int)
    NewLine

