# Turn source text into a sequence of tokens

import std
from utils import panic
from std import print, ord, str_slice, str_len
from std import str_to_float, str_to_int
from token import Token, TokenKind, token_to_string
from location import Location, location_at, Position
from strlib import hex_to_int
from datatypes import List, Option


class Lexer:
    var pending: List[Token] = List()
    var indent_stack: List[int] = List()
    var at_bol: bool = true  # at begin-of-line (bol)
    var at_end: bool = false
    var spaces: int = 0
    var source: str = ""
    var source_length: int = 0

    var tok_begin: int = 0
    var offset: int = 0
    var row: int = 1
    var col_start: int = 0  # Offset in source of this line
    var start_col: int = 1  # Offset added to column

    fn init(source: str):
        this.source = source
        source_length = str_len(source)
        at_end = false
        at_bol = true
        row = 1
        indent_stack.append(0)

    fn next_token() -> Token:
        while pending.is_empty() and not at_end:
            work_some()
        
        if pending.is_empty():
            return Token(kind: TokenKind.Eof(), location: location_at(row: row, column: 1))
        else:
            return pending.pop_front()
    
    fn pushback_token(token: Token):
        pending.prepend(token)

    fn work_some():
        let tok = next_token2()
        # print("EHHH: {token_to_string(tok)}")
        case tok.kind:
            Eof:
                at_end = true

                if not at_bol:
                    emit_token(kind: TokenKind.NewLine(), location: location_at(row: row, column: 1))

                # Dedent to top level!
                while indent_stack.len() > 1:
                    let tmp = indent_stack.pop_front()
                    emit_token(kind: TokenKind.Dedent(), location: location_at(row: row, column: 1))

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
                            panic("Indentation error")
                        emit_token(kind: TokenKind.Dedent(), location: tok.location)

            # print("ehhh -> " + token_to_string(tok))
            emit(tok)

    fn on_newline(tok: Token):
        if not at_bol:
            emit(tok)
        at_bol = true
        spaces = 0
        row += 1
    
    fn emit(tok: Token):
        pending.append(tok)
    
    fn emit_token(kind: TokenKind, location: Location):
        emit(tok: Token(kind, location))

    fn next_token2() -> Token:
        let n = source_length
        if offset < n:
            # Start of new token:
            tok_begin = offset
            let kind = TokenKind.Error()
            let begin_column = tok_begin - col_start + start_col
            let begin = Position(row: row, column: begin_column)

            # Get char:
            let c = next_char()

            # Decide what to do based on char:
            if c == '(':
                kind = TokenKind.BraceOpen()
            elif c == ')':
                kind = TokenKind.BraceClose()
            elif c == '[':
                kind = TokenKind.BracketOpen()
            elif c == ']':
                kind = TokenKind.BracketClose()
            elif c == ',':
                kind = TokenKind.Comma()
            elif c == '.':
                kind = TokenKind.Dot()
            elif c == ':':
                kind = TokenKind.Colon()
            elif c == ' ':
                while match(txt: ' '):
                    pass
                kind = TokenKind.Space(amount: std.str_len(get_lexeme()))
            elif c == '#':
                # Line comment
                while offset < n and not is_lf(c: peek()):
                    offset += 1
                offset += 1
                kind = TokenKind.Comment(comment: get_lexeme())
                col_start = offset
            elif ord(c) == 34:
                while offset < n and not (ord(c: peek()) == 34):
                    offset += 1
                offset += 1
                # String
                let txt: str = get_lexeme()
                txt = str_slice(value: txt, begin: 1, end: str_len(txt) - 1)
                kind = TokenKind.String(txt)
            elif c == '-':
                if match(txt: '>'):
                    kind = TokenKind.Arrow()
                elif match(txt: '='):
                    kind = TokenKind.MinusEquals()
                else:
                    kind = TokenKind.Minus()
            elif c == '+':
                if match(txt: '='):
                    kind = TokenKind.PlusEquals()
                else:
                    kind = TokenKind.Plus()
            elif c == '?':
                kind = TokenKind.Question()
            elif c == '/':
                kind = TokenKind.Slash()
            elif c == '*':
                kind = TokenKind.Asterix()
            elif is_lf(c):
                kind = TokenKind.NewLine()
                col_start = offset
            elif is_digit(c):
                let is_hex = false
                if c == '0' and offset < n:
                    if peek() == 'x':
                        is_hex = true
                    elif peek() == 'X':
                        is_hex = true

                if is_hex:
                    offset += 1
                    # Hex number!
                    while offset < n and is_hex_digit(c: peek()):
                        offset += 1
                    let hextext = get_lexeme()
                    hextext = str_slice(value: hextext, begin: 2, end: str_len(hextext))
                    let int_value = hex_to_int(hextext)
                    kind = TokenKind.Integer(int_value)
                else:
                    while offset < n and is_digit(c: peek()):
                        offset += 1
                    if offset < n and peek() == '.':
                        # Floating point!
                        offset += 1
                        while offset < n and is_digit(c: peek()):
                            offset += 1
                        let val2 = get_lexeme()
                        let float_value: float = str_to_float(val2)
                        kind = TokenKind.Float(float_value)
                    else:
                        # Normal decimal number
                        let int_value: int = str_to_int(get_lexeme())
                        kind = TokenKind.Integer(int_value)
            elif is_id(c):
                while offset < n and is_id_or_digit(c: peek()):
                    offset += 1

                # Check for keywords:
                kind = check_keyword(txt: get_lexeme())

            elif ord(c) == 39:
                # Char literal
                offset += 2
                # TODO: check closing '
                let char_value = std.str_get(value: get_lexeme(), index: 1)
                kind = TokenKind.Char(char_value)

            elif c == '<':
                if match(txt: '='):
                    kind = TokenKind.LessEquals()
                else:
                    kind = TokenKind.Less()
            elif c == '>':
                if match(txt: '='):
                    kind = TokenKind.GreaterEquals()
                else:
                    kind = TokenKind.Greater()
            elif c == '=':
                if match(txt: '='):
                    kind = TokenKind.EqualsEquals()
                else:
                    kind = TokenKind.Equals()
            elif c == '!':
                if match(txt: '='):
                    kind = TokenKind.NotEquals()

            let end_column = offset - 1
            end_column = end_column - col_start + start_col
                
            let end = Position(row: row, column: end_column)
            let location = Location(begin, end)

            return Token(kind, location)
        else:
            return Token(kind: TokenKind.Eof(), location: location_at(row: row, column: 1))
    
    fn peek() -> char:
        let n = source_length
        if offset < n:
            let c = std.str_get(text: source, index: offset)
            return c
        else:
            panic("Peek beyond input")
    
    fn next_char() -> char:
        let n = source_length
        if offset < n:
            let c = std.str_get(text: source, index: offset)
            offset += 1
            return c
        else:
            panic("Next char beyond input")

    fn match(txt: char) -> bool:
        let n = source_length
        if offset < n:
            let c = std.str_get(text: source, index: offset)
            if c == txt:
                offset += 1
                return true
            else:
                return false
        else:
            return false
    
    fn get_lexeme() -> str:
        return std.str_slice(value: source, begin: tok_begin, end: offset)

fn is_lf(c: char) -> bool:
    let o = ord(value: c)
    return o == 10

fn is_digit(c: char) -> bool:
    # Check if a character is a digit.
    let o = ord(value: c)
    return (o >= 48) and (o <= 57)

fn is_hex_digit(c: char) -> bool:
    # Check if a character is a hex digit.
    let o = ord(value: c)
    if (o >= 48) and (o <= 57):     # 0..9
        return true
    elif (o >= 65) and (o <= 70):   # A..F
        return true
    elif (o >= 97) and (o <= 102):  # a..f
        return true
    else:
        return false

fn is_id(c: char) -> bool:
    let o = ord(c)
    if (o >= 65) and (o <= 90):
        return true
    elif (o >= 97) and (o <= 122):
        return true
    elif c == '_':
        return true
    else:
        return false

fn is_id_or_digit(c: char) -> bool:
    return is_id(c) or is_digit(c)

fn check_keyword(txt: str) -> TokenKind:
    let kind = TokenKind.Identifier(txt)
    if txt == "and":
        kind = TokenKind.KwAnd()
    elif txt == "break":
        kind = TokenKind.KwBreak()
    elif txt == "case":
        kind = TokenKind.KwCase()
    elif txt == "class":
        kind = TokenKind.KwClass()
    elif txt == "continue":
        kind = TokenKind.KwContinue()
    elif txt == "else":
        kind = TokenKind.KwElse()
    elif txt == "elif":
        kind = TokenKind.KwElif()
    elif txt == "enum":
        kind = TokenKind.KwEnum()
    elif txt == "except":
        kind = TokenKind.KwExcept()
    elif txt == "extern":
        kind = TokenKind.KwExtern()
    elif txt == "fn":
        kind = TokenKind.KwFn()
    elif txt == "for":
        kind = TokenKind.KwFor()
    elif txt == "from":
        kind = TokenKind.KwFrom()
    elif txt == "if":
        kind = TokenKind.KwIf()
    elif txt == "import":
        kind = TokenKind.KwImport()
    elif txt == "in":
        kind = TokenKind.KwIn()
    elif txt == "let":
        kind = TokenKind.KwLet()
    elif txt == "loop":
        kind = TokenKind.KwLoop()
    elif txt == "not":
        kind = TokenKind.KwNot()
    elif txt == "or":
        kind = TokenKind.KwOr()
    elif txt == "pass":
        kind = TokenKind.KwPass()
    elif txt == "pub":
        kind = TokenKind.KwPub()
    elif txt == "raise":
        kind = TokenKind.KwRaise()
    elif txt == "return":
        kind = TokenKind.KwReturn()
    elif txt == "struct":
        kind = TokenKind.KwStruct()
    elif txt == "switch":
        kind = TokenKind.KwSwitch()
    elif txt == "try":
        kind = TokenKind.KwTry()
    elif txt == "var":
        kind = TokenKind.KwVar()
    elif txt == "while":
        kind = TokenKind.KwWhile()
    elif txt == "true":
        kind = TokenKind.Bool(value: true)
    elif txt == "false":
        kind = TokenKind.Bool(value: false)

    return kind
