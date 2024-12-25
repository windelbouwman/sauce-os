"""Lexical analysis."""

from typing import Iterable, Any
from dataclasses import dataclass
from .errors import ParseError
from .location import Location, Position
import re


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
                    level_stack.pop()
                if new_indentation != level_stack[-1]:
                    lex_error(
                        loc,
                        f"Indendation error: {new_indentation} spaces, but expected {level_stack[-1]} spaces",
                    )
            elif new_indentation > level_stack[-1]:
                yield Token("INDENT", "", loc)
                level_stack.append(new_indentation)
            yield token


KEYWORDS = {
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


def spec_to_pattern(token_spec):
    regex = "|".join(f"(?P<{name}>{pattern})" for name, pattern in token_spec)
    return re.compile(regex, re.MULTILINE | re.DOTALL)


def tokenize(code: str | tuple[Location, str]):
    newline_regex = r"\n"
    main_pattern = spec_to_pattern(
        [
            ("HEXNUMBER", r"0x[0-9a-fA-F]+"),
            ("BINNUMBER", r"0b[0-1]+"),
            ("FNUMBER1", r"[0-9]+[eE][\-+]?[0-9]+"),  # 1e9
            ("FNUMBER2", r"[0-9]+\.[0-9]+[eE][\-+]?[0-9]+"),  # 1.0e9
            ("FNUMBER3", r"[0-9]+\.[0-9]+"),  # 1.0
            ("NUMBER", r"[0-9]+"),
            ("OP2", r"(->)|(\+=)|(\-=)|(\*=)|(\/=)|(<<)|(>>)|(==)|(<=)|(!=)|(>=)"),
            ("OP", r"[\(\):+\-\*/\.,<>=^\|&{}\[\]\?]"),
            ("ID", r"[A-Za-z][A-Za-z_0-9]*"),
            ("SPACE", r"[ ]+"),
            ("DOCSTRING", r"\"\"\".*?\"\"\""),
            ("STRING_START", r"\""),
            ("CHAR", r"\'[^\']\'"),
            ("NEWLINE", newline_regex),
            ("COMMENT", r"#[^\n]*\n"),
            ("OTHER", r"."),
        ]
    )
    string_pattern = spec_to_pattern(
        [
            ("STRING_LITERAL", r"[^\"\\\{]+"),
            ("ESCAPESEQUENCE", r"\\."),
            ("STRING_END", r"\""),
            ("STRING_INTERP", r"\{"),
            ("OTHER", r"."),
        ]
    )
    patterns = {
        "normal": main_pattern,
        "string": string_pattern,
    }

    assert isinstance(code, str)
    start_row = start_col = 1
    row, col = start_row, start_col
    col_start = 0
    pos = 0
    mode = "normal"  # or string!
    curly_stack = []

    while pos < len(code):
        mo = patterns[mode].match(code, pos)
        if mo is None:
            raise RuntimeError(f"No match at {pos}")
        pos = mo.end()

        # print(mo)
        kind: str = mo.lastgroup
        value = mo.group()
        col = mo.start() - col_start + start_col
        col2 = mo.end() - col_start + start_col
        loc = Location(Position(row, col), Position(row, col2))

        if mode == "normal":
            if kind == "OP" or kind == "OP2":
                kind = value
                if kind == "}":
                    x = curly_stack.pop()
                    if x == "STRING_INTERP":
                        mode = "string"
                    else:
                        raise NotImplementedError(f"Curly: {x}")
                elif kind == "{":
                    curly_stack.append(kind)
            elif kind == "ID":
                if value in KEYWORDS:
                    kind = "KW_" + value.upper()
                elif value == "true":
                    kind = "BOOL"
                    value = True
                elif value == "false":
                    kind = "BOOL"
                    value = False
            elif kind == "STRING_START":
                mode = "string"
            elif kind == "DOCSTRING":
                value = value[3:-3]
                newlines = len(re.findall(newline_regex, value))
                row += newlines
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
            elif kind == "FNUMBER1" or kind == "FNUMBER2" or kind == "FNUMBER3":
                kind = "FNUMBER"
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
        elif mode == "string":
            if kind == "STRING_LITERAL":
                pass
            elif kind == "STRING_END":
                mode = "normal"
            elif kind == "STRING_INTERP":
                curly_stack.append(kind)
                mode = "normal"
                kind = "{"
            elif kind == "ESCAPESEQUENCE":
                kind = "STRING_LITERAL"
                value = value[1]
            else:
                raise NotImplementedError(kind)
        else:
            raise NotImplementedError(mode)

        tok = Token(kind, value, loc)
        yield tok

    end_loc = Location(Position(row, 1), Position(row, 1))
    yield Token("EOF", "EOF", end_loc)


def lex_error(location: Location, message: str):
    raise ParseError(location, message)
