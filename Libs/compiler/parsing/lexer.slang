""" Turn source text into a sequence of tokens
"""

import std
from utils import panic, assert
from std import print, ord, chr, str_slice, str_len
from std import str_to_float
from token import Token, TokenKind
from location import Location, location_at, Position
from strlib import is_digit, digit_to_int, is_hex_digit, hex_digit_to_int, is_bin_digit, bin_digit_to_int, is_lf
from datatypes import List, Option
from deque import Queue, new_queue
from dicttype import Dictionary

enum LexerMode:
    Normal
    String

class Lexer:
    var pending: Queue[Token] = new_queue(capacity: 7)
    var indent_stack: List[int] = List()
    var at_bol: bool = true  # at begin-of-line (bol)
    var at_end: bool = false
    var spaces: int = 0
    var source: str = ""
    var source_length: int = 0
    var m_keywords: Dictionary[TokenKind] = Dictionary()

    var m_mode: LexerMode = LexerMode.Normal()
    var tok_begin: int = 0
    var offset: int = 0

    fn init(source: str):
        fill_keyword_dictionary(keywords: m_keywords)
        this.source = source
        offset = 0
        source_length = str_len(text: source)
        at_end = false
        at_bol = true
        indent_stack.append(0)

    fn next_token() -> Token:
        while pending.is_empty() and not at_end:
            work_some()

        if pending.is_empty():
            Token(kind: TokenKind.Eof(), location: location_at(offset))
        else:
            pending.pop()

    fn work_some():
        let tok = next_token2()

        case tok.kind:
            Eof:
                at_end = true

                if not at_bol:
                    emit_token(kind: TokenKind.NewLine(), location: location_at(offset))

                # Dedent to top level!
                while indent_stack.len() > 1:
                    let tmp = indent_stack.pop_front()
                    emit_token(kind: TokenKind.Dedent(), location: location_at(offset))
            Space(x):
                if at_bol:
                    spaces += x
            NewLine:
                on_newline(tok)
            Comment(x):
                tok.kind = TokenKind.NewLine()
                on_newline(tok)
        else:
            if at_bol:
                at_bol = false
                if spaces > indent_stack.last():
                    # 1x indent!
                    indent_stack.append(spaces)

                    emit_token(kind: TokenKind.Indent(), location: tok.location)
                else:
                    while spaces < indent_stack.last():
                        # n times dedent!
                        let tmp = indent_stack.pop_last()
                        if tmp < spaces:
                            emit_token(kind: TokenKind.Error("Indentation error"), location: tok.location)
                        emit_token(kind: TokenKind.Dedent(), location: tok.location)

                    if spaces != indent_stack.last():
                        emit_token(kind: TokenKind.Error("Indentation error"), location: tok.location)

            emit(tok)

    fn on_newline(tok: Token):
        if not at_bol:
            emit(tok)
        at_bol = true
        spaces = 0

    fn emit(tok: Token):
        pending.push(tok)

    fn emit_token(kind: TokenKind, location: Location):
        emit(tok: Token(kind, location))

    fn next_token2() -> Token:
        if offset < source_length:
            # Start of new token:
            tok_begin = offset

            let kind = case m_mode:
                Normal:
                    parse_normal_token()
                String:
                    parse_string_token()

            let location = Location(begin: tok_begin, end: offset - 1)
            Token(kind, location)
        else:
            Token(kind: TokenKind.Eof(), location: location_at(offset))

    fn parse_normal_token() -> TokenKind:
        # Get char:
        let c = next_char()

        # Decide what to do based on char:
        if is_id(c):
            parse_identifier()
        elif c == ' ':
            while match(' '):
                pass
            TokenKind.Space(amount: std.str_len(text: get_lexeme()))
        elif c == '(':
            TokenKind.ParenthesisOpen()
        elif c == ')':
            TokenKind.ParenthesisClose()
        elif c == '[':
            TokenKind.BracketOpen()
        elif c == ']':
            TokenKind.BracketClose()
        elif c == '}':
            m_mode = LexerMode.String()
            TokenKind.BraceClose()
        elif c == ',':
            TokenKind.Comma()
        elif c == '.':
            TokenKind.Dot()
        elif c == ':':
            TokenKind.Colon()
        elif c == '#':
            parse_line_comment()
        elif c == '"':
            parse_string()
        elif c == '-':
            if match('>'):
                TokenKind.Arrow()
            elif match('='):
                TokenKind.MinusEquals()
            else:
                TokenKind.Minus()
        elif c == '+':
            if match('='):
                TokenKind.PlusEquals()
            else:
                TokenKind.Plus()
        elif c == '?':
            TokenKind.Question()
        elif c == '/':
            TokenKind.Slash()
        elif c == '*':
            TokenKind.Asterix()
        elif is_lf(c):
            TokenKind.NewLine()
        elif is_digit(c):
            parse_number(c)
        elif ord(c) == 39:
            parse_char()
        elif c == '<':
            if match('='):
                TokenKind.LessEquals()
            elif match('<'):
                TokenKind.ShiftLeft()
            else:
                TokenKind.Less()
        elif c == '>':
            if match('='):
                TokenKind.GreaterEquals()
            elif match('>'):
                TokenKind.ShiftRight()
            else:
                TokenKind.Greater()
        elif c == '=':
            if match('='):
                TokenKind.EqualsEquals()
            else:
                TokenKind.Equals()
        elif c == '!':
            if match('='):
                TokenKind.NotEquals()
            else:
                TokenKind.Error("Invalid token")
        elif c == '|':
            TokenKind.BitOr()
        elif c == '&':
            TokenKind.BitAnd()
        elif c == '^':
            TokenKind.BitXor()
        else:
            TokenKind.Error("Unknown char: '{c}'")

    fn parse_string_token() -> TokenKind:
        let c = next_char()

        if c == '"':
            m_mode = LexerMode.Normal()
            TokenKind.StringEnd()
        elif c == '{':
            m_mode = LexerMode.Normal()
            TokenKind.BraceOpen()
        elif c == '\':
            offset += 1
            let text: str = get_lexeme()
            assert(condition: str_len(text) == 2, message: "Escape sequence must contain 2 characters.")
            text = str_slice(text, begin: 1, end: 2)
            TokenKind.StringContent(text)
        else:
            while offset < source_length:
                c = peek()
                if c == '"' or c == '{' or c == '\':
                    break
                offset += 1
            TokenKind.StringContent(get_lexeme())

    fn parse_line_comment() -> TokenKind:
        let n = source_length
        while offset < n and not is_lf(c: peek()):
            offset += 1
        offset += 1
        TokenKind.Comment(comment: get_lexeme())

    fn parse_identifier() -> TokenKind:
        while is_id_or_digit(c: peek()):
            offset += 1

        # Check for keywords:
        let txt = get_lexeme()
        case m_keywords.maybe_get(key: txt):
            Some(k2):
                k2
            None:
                TokenKind.Identifier(txt)

    fn parse_char() -> TokenKind:
        """ Char literal """
        offset += 1
        if ord(peek()) == 39:
            offset += 1
            if offset < source_length:
                let char_value = std.str_get(text: get_lexeme(), index: 1)
                TokenKind.Char(char_value)
            else:
                TokenKind.Error("Invalid char")
        else:
            TokenKind.Error("Invalid char")

    fn parse_string() -> TokenKind:
        if peek() == '"' and peek_n(n: 1) == '"':
            offset += 2
            parse_doc_string()
        else:
            m_mode = LexerMode.String()
            TokenKind.StringStart()

    fn parse_doc_string() -> TokenKind:
        """ Parse a doc string, like this one :) """
        let n = source_length
        let z = 0
        while offset < n:
            let c2 = next_char()
            if c2 == '"':
                z += 1
                if z == 3:
                    break
            else:
                z = 0
        let text: str = get_lexeme()
        TokenKind.DocString(text)

    fn parse_number(c: char) -> TokenKind:
        let n = source_length
        let is_hex = false
        let is_bin = false
        if c == '0':
            if peek() == 'x':
                is_hex = true
                offset += 1
            elif peek() == 'b':
                is_bin = true
                offset += 1

        if is_hex:
            let value = 0
            loop:
                c = peek()
                if is_hex_digit(c):
                    value = value * 16 + hex_digit_to_int(c)
                    offset += 1
                else:
                    break
            TokenKind.Integer(value)
        elif is_bin:
            let value = 0
            loop:
                c = peek()
                if is_bin_digit(c):
                    value = value * 2 + bin_digit_to_int(c)
                    offset += 1
                else:
                    break
            TokenKind.Integer(value)
        else:
            # Calculate value as we go through the digits:
            let value = digit_to_int(c)
            loop:
                c = peek()
                if is_digit(c):
                    value = value * 10 + digit_to_int(c)
                    offset += 1
                else:
                    break
            if peek() == '.':
                offset += 1
                parse_float(before: value)
            elif peek() == 'e':
                parse_exponent(base: value)
            else:
                # Normal decimal number
                TokenKind.Integer(value)

    fn parse_float(before: int) -> TokenKind:
        while is_digit(c: peek()):
            offset += 1
        if peek() == 'e':
            parse_exponent(base: 0)
        else:
            let float_value: float = str_to_float(get_lexeme())
            TokenKind.Float(float_value)

    fn parse_exponent(base: int) -> TokenKind:
        """ Parse the exponent notation after the 'e'"""
        offset += 1
        let sign = 1
        if peek() == '+':
            offset += 1
        elif peek() == '-':
            sign = -1
            offset += 1

        if is_digit(c: peek()):
            while is_digit(c: peek()):
                offset += 1
            let float_value: float = str_to_float(get_lexeme())
            TokenKind.Float(float_value)
        else:
            TokenKind.Error("Invalid exponent notation")

    fn peek() -> char:
        peek_n(n: 0)

    fn peek_n(n: int) -> char:
        let index = offset + n
        if index < source_length:
            std.str_get(text: source, index)
        else:
            chr(0)

    fn next_char() -> char:
        let n = source_length
        if offset < n:
            let c = std.str_get(text: source, index: offset)
            offset += 1
            c
        else:
            panic("Next char beyond input")

    fn match(txt?: char) -> bool:
        let n = source_length
        if offset < n:
            let c = std.str_get(text: source, index: offset)
            if c == txt:
                offset += 1
                true
            else:
                false
        else:
            false

    fn get_lexeme() -> str:
        std.str_slice(text: source, begin: tok_begin, end: offset)

fn is_id(c: char) -> bool:
    let o = ord(c)
    if (o >= 97) and (o <= 122):  # 'a' .. 'z' (most common case)
        true
    elif (o >= 65) and (o <= 90):  # 'A' .. 'Z'
        true
    elif c == '_':
        true
    else:
        false

fn is_id_or_digit(c: char) -> bool:
    is_id(c) or is_digit(c)

fn fill_keyword_dictionary(keywords: Dictionary[TokenKind]):
    keywords.insert(key: "and", value: TokenKind.KwAnd())
    keywords.insert(key: "break", value: TokenKind.KwBreak())
    keywords.insert(key: "case", value: TokenKind.KwCase())
    keywords.insert(key: "class", value: TokenKind.KwClass())
    keywords.insert(key: "continue", value: TokenKind.KwContinue())
    keywords.insert(key: "else", value: TokenKind.KwElse())
    keywords.insert(key: "elif", value: TokenKind.KwElif())
    keywords.insert(key: "enum", value: TokenKind.KwEnum())
    keywords.insert(key: "except", value: TokenKind.KwExcept())
    keywords.insert(key: "extern", value: TokenKind.KwExtern())
    keywords.insert(key: "fn", value: TokenKind.KwFn())
    keywords.insert(key: "for", value: TokenKind.KwFor())
    keywords.insert(key: "from", value: TokenKind.KwFrom())
    keywords.insert(key: "if", value: TokenKind.KwIf())
    keywords.insert(key: "import", value: TokenKind.KwImport())
    keywords.insert(key: "in", value: TokenKind.KwIn())
    keywords.insert(key: "let", value: TokenKind.KwLet())
    keywords.insert(key: "loop", value: TokenKind.KwLoop())
    keywords.insert(key: "macro", value: TokenKind.KwMacro())
    keywords.insert(key: "not", value: TokenKind.KwNot())
    keywords.insert(key: "or", value: TokenKind.KwOr())
    keywords.insert(key: "pass", value: TokenKind.KwPass())
    keywords.insert(key: "pub", value: TokenKind.KwPub())
    keywords.insert(key: "raise", value: TokenKind.KwRaise())
    keywords.insert(key: "return", value: TokenKind.KwReturn())
    keywords.insert(key: "struct", value: TokenKind.KwStruct())
    keywords.insert(key: "switch", value: TokenKind.KwSwitch())
    keywords.insert(key: "try", value: TokenKind.KwTry())
    keywords.insert(key: "var", value: TokenKind.KwVar())
    keywords.insert(key: "while", value: TokenKind.KwWhile())
    keywords.insert(key: "true", value: TokenKind.Bool(value: true))
    keywords.insert(key: "false", value: TokenKind.Bool(value: false))
