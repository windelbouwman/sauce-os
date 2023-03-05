""" Lexical analysis.
"""

from typing import Iterable
from .errors import print_error, LexError
from .location import Location
import logging
import re

logger = logging.getLogger('lexer')


class Lexer:
    def __init__(self):
        pass


class Token:
    def __init__(self, ty: str, value, location: Location):
        self.ty = ty
        self.value = value
        self.location = location

    def __repr__(self):
        return f'TOK(ty={self.ty}, val={self.value},loc={self.location})'


def detect_indentations(code: str, tokens: Iterable[Token]):
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
                        code, loc, f"Indendation error: {new_indentation} spaces, but expected {level_stack[-1]} spaces")
            elif new_indentation > level_stack[-1]:
                yield Token('INDENT', '', loc)
                level_stack.append(new_indentation)
            yield token

    while len(level_stack) > 1:
        level_stack.pop()
        yield Token('DEDENT', '', Location(0, 0))


def tokenize(code: str):
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
        'fn', 'import', 'in',
        'if', 'else', 'elif',
        'and', 'or',
        'loop', 'break', 'continue', 'for', 'while',
        'class', 'return',
        'struct', 'enum', 'pass',
        'let', 'mut'
    }

    regex = '|'.join(f'(?P<{name}>{pattern})' for name, pattern in token_spec)
    # print('Using regex', regex)
    row = 1
    col = 1
    col_start = 0
    for mo in re.finditer(regex, code, re.MULTILINE | re.DOTALL):
        # print(mo)
        kind: str = mo.lastgroup
        value = mo.group()
        col = mo.start() - col_start + 1
        loc = Location(row, col)
        if kind == 'OP' or kind == 'OP2':
            tok = Token(value, value, loc)
        elif kind == 'ID':
            if value in keywords:
                kind = value
            tok = Token(kind, value, loc)
        elif kind == 'STRING':
            tok = Token(kind, value, loc)
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
            lex_error(code, loc, f'Lexing exception at {loc}: {value}')
        else:
            raise NotImplementedError(kind)

        # logger.debug(f'Got token: {tok}')
        yield tok


def lex_error(code: str, location: Location, message: str):
    print_error(code, location, message)
    raise LexError(message)
