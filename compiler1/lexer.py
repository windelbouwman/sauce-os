""" Lexical analysis.
"""

from typing import Iterable, Any
from dataclasses import dataclass
from .errors import ParseError
from .location import Location, Position
import logging
import re

logger = logging.getLogger("lexer")


@dataclass
class Token:
    ty: str
    value: Any
    location: "Location"


def detect_indentations(tokens: Iterable[Token]):
    """Funky function to inject indentation tokens."""
    bol = True  # beginning of line
    level_stack = [0]
    new_indentation = 0
    for token in tokens:
        if token.ty == "SPACE":
            if bol:
                new_indentation += len(token.value)
        elif token.ty == "NEWLINE":
            if not bol:
                yield token
            new_indentation = 0
            bol = True
        elif token.ty == "EOF":
            end_loc = token.location
            if not bol:
                yield Token("NEWLINE", "NEWLINE", end_loc)

            while len(level_stack) > 1:
                level_stack.pop()
                yield Token("DEDENT", "", end_loc)

            yield token
        else:
            bol = False
            loc = token.location
            if new_indentation < level_stack[-1]:
                while new_indentation < level_stack[-1]:
                    yield Token("DEDENT", "", loc)
                    old_indentation = level_stack.pop()
                if new_indentation != level_stack[-1]:
                    lex_error(
                        loc,
                        f"Indendation error: {new_indentation} spaces, but expected {level_stack[-1]} spaces",
                    )
            elif new_indentation > level_stack[-1]:
                yield Token("INDENT", "", loc)
                level_stack.append(new_indentation)
            yield token


def tokenize(code: str | tuple[Location, str]):
    token_spec = [
        ("OP2", r"(->)|(\+=)|(\-=)|(<<)|(>>)|(==)|(<=)|(!=)|(>=)"),
        ("OP", r"[\(\):+\-\*/\.,<>=^\|&{}\[\]\?]"),
        ("ID", r"[A-Za-z][A-Za-z_0-9]*"),
        ("HEXNUMBER", r"0x[0-9a-fA-F]+"),
        ("BINNUMBER", r"0b[0-1]+"),
        ("FNUMBER", r"[0-9]+\.[0-9]+"),
        ("NUMBER", r"[0-9]+"),
        ("SPACE", r"[ ]+"),
        ("STRING", r"\"[^\"]*\""),
        ("CHAR", r"\'[^\']\'"),
        ("NEWLINE", r"\n"),
        ("COMMENT", r"#[^\n]*\n"),
        ("OTHER", r"."),
    ]

    keywords = {
        "and",
        "break",
        "case",
        "class",
        "continue",
        "else",
        "elif",
        "enum",
        "except",
        "extern",
        "fn",
        "for",
        "from",
        "if",
        "import",
        "in",
        "let",
        "loop",
        "mut",
        "not",
        "or",
        "pass",
        "pub",
        "raise",
        "return",
        "struct",
        "switch",
        "try",
        "type",
        "var",
        "while",
    }

    regex = "|".join(f"(?P<{name}>{pattern})" for name, pattern in token_spec)
    if isinstance(code, tuple):
        start_location, code = code
        start_row, start_col = start_location.begin.row, start_location.begin.column
    else:
        assert isinstance(code, str)
        start_row = start_col = 1
    row, col = start_row, start_col
    col_start = 0

    for mo in re.finditer(regex, code, re.MULTILINE | re.DOTALL):
        # print(mo)
        kind: str = mo.lastgroup
        value = mo.group()
        col = mo.start() - col_start + start_col
        col2 = mo.end() - col_start + start_col
        loc = Location(Position(row, col), Position(row, col2))
        if kind == "OP" or kind == "OP2":
            kind = value
        elif kind == "ID":
            if value in keywords:
                kind = "KW_" + value.upper()
            elif value == "true":
                kind = "BOOL"
                value = True
            elif value == "false":
                kind = "BOOL"
                value = False
        elif kind == "STRING":
            value = value[1:-1]
        elif kind == "CHAR":
            value = value[1:-1]
        elif kind == "NUMBER":
            value = int(value)
        elif kind == "HEXNUMBER":
            kind = "NUMBER"
            value = int(value, 16)
        elif kind == "BINNUMBER":
            kind = "NUMBER"
            value = int(value, 2)
        elif kind == "FNUMBER":
            value = float(value)
        elif kind == "SPACE":
            pass
        elif kind == "NEWLINE":
            col_start = mo.end()
            row += 1
        elif kind == "COMMENT":
            # Register line comment as newline!
            kind = "NEWLINE"
            col_start = mo.end()
            row += 1
        elif kind == "OTHER":
            if value.isprintable():
                c = value
            else:
                c = str(value.encode(encoding="utf-8", errors="replace"))
            lex_error(loc, f"Unexpected character: {c}")
        else:
            raise NotImplementedError(kind)

        # logger.debug(f'Got token: {tok}')
        tok = Token(kind, value, loc)
        yield tok

    end_loc = Location(Position(row, 1), Position(row, 1))
    yield Token("EOF", "EOF", end_loc)


def lex_error(location: Location, message: str):
    raise ParseError(location, message)
