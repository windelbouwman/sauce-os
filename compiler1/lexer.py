""" Lexical analysis.
"""

from typing import Iterable
from .errors import ParseError
from .location import Location
import logging
import re

logger = logging.getLogger('lexer')


class Token:
    def __init__(self, ty: str, value, location: Location):
        self.ty = ty
        self.value = value
        self.location = location

    def __repr__(self):
        return f'TOK(ty={self.ty}, val={self.value},loc={self.location})'


def detect_indentations(tokens: Iterable[Token]):
    """ Funky function to inject indentation tokens.
    """
    bol = True  # beginning of line
    level_stack = [0]
    new_indentation = 0
    for token in tokens:
        if token.ty == 'SPACE':
            if bol:
                new_indentation += len(token.value)
        elif token.ty == 'NEWLINE':
            if not bol:
                yield token
            new_indentation = 0
            bol = True
        else:
            bol = False
            loc = token.location
            if new_indentation < level_stack[-1]:
                while new_indentation < level_stack[-1]:
                    yield Token('DEDENT', '', loc)
                    old_indentation = level_stack.pop()
                if new_indentation != level_stack[-1]:
                    lex_error(
                        loc, f"Indendation error: {new_indentation} spaces, but expected {level_stack[-1]} spaces")
            elif new_indentation > level_stack[-1]:
                yield Token('INDENT', '', loc)
                level_stack.append(new_indentation)
            yield token

    end_loc = Location(0xffffffff, 1)
    if not bol:
        yield Token('NEWLINE', 'NEWLINE', end_loc)

    while len(level_stack) > 1:
        level_stack.pop()
        yield Token('DEDENT', '', end_loc)


def tokenize(code: str | tuple[Location, str]):
    token_spec = [
        ("OP2", r"(->)|(::)|(==)|(<=)|(!=)|(>=)"),
        ("OP", r"[\(\):+\-\*/\.,<>={}\[\]]"),
        ("ID", r"[A-Za-z][A-Za-z_0-9]*"),
        ("FNUMBER", r"[0-9]+\.[0-9]+"),
        ("NUMBER", r"[0-9]+"),
        ("SPACE", r"[ ]+"),
        ("STRING", r"\"[^\"]*\""),
        ("NEWLINE", r"\n"),
        ("COMMENT", r"#[^\n]*\n"),
        ("OTHER", r"."),
    ]

    keywords = {
        'and': 'KW_AND',
        'break': 'KW_BREAK',
        'case': 'KW_CASE',
        'class': 'KW_CLASS',
        'continue': 'KW_CONTINUE',
        'else': 'KW_ELSE',
        'elif': 'KW_ELIF',
        'enum': 'KW_ENUM',
        'fn': 'KW_FN',
        'for': 'KW_FOR',
        'from': 'KW_FROM',
        'if': 'KW_IF',
        'import': 'KW_IMPORT',
        'in': 'KW_IN',
        'let': 'KW_LET',
        'loop': 'KW_LOOP',
        'mut': 'KW_MUT',
        'or': 'KW_OR',
        'pass': 'KW_PASS',
        'return': 'KW_RETURN',
        'struct': 'KW_STRUCT',
        'switch': 'KW_SWITCH',
        'type': 'KW_TYPE',
        'var': 'KW_VAR',
        'while': 'KW_WHILE'
    }

    regex = '|'.join(f'(?P<{name}>{pattern})' for name, pattern in token_spec)
    if isinstance(code, tuple):
        start_row, start_col = code[0].row, code[0].column
        code = code[1]
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
        loc = Location(row, col)
        if kind == 'OP' or kind == 'OP2':
            tok = Token(value, value, loc)
        elif kind == 'ID':
            if value in keywords:
                kind = keywords[value]
            elif value == 'true':
                kind = 'BOOL'
                value = True
            elif value == 'false':
                kind = 'BOOL'
                value = False
            tok = Token(kind, value, loc)
        elif kind == 'STRING':
            tok = Token(kind, value[1:-1], loc)
        elif kind == 'NUMBER':
            value = int(value)
            tok = Token(kind, value, loc)
        elif kind == 'FNUMBER':
            value = float(value)
            tok = Token(kind, value, loc)
        elif kind == 'SPACE':
            tok = Token(kind, value, loc)
        elif kind == 'NEWLINE':
            tok = Token(kind, value, loc)
            col_start = mo.end()
            row += 1
        elif kind == 'COMMENT':
            # Register line comment as newline!
            tok = Token('NEWLINE', value, loc)
            col_start = mo.end()
            row += 1
        elif kind == 'OTHER':
            lex_error(loc, f'Lexing exception at {loc}: {value}')
        else:
            raise NotImplementedError(kind)

        # logger.debug(f'Got token: {tok}')
        yield tok


def lex_error(location: Location, message: str):
    raise ParseError(location, message)
