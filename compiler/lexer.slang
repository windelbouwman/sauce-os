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
        this.source_length = str_len(source)
        this.at_end = false
        this.at_bol = true
        this.row = 1
        this.indent_stack.append(0)

    fn next_token() -> Token:
        while this.pending.is_empty() and not this.at_end:
            this.work_some()
        
        if this.pending.is_empty():
            return Token(kind: TokenKind.Eof(), location: location_at(row: this.row, column: 1))
        else:
            return this.pending.pop_front()
    
    fn pushback_token(token: Token):
        this.pending.prepend(token)

    fn work_some():
        let tok = this.next_token2()
        # print("EHHH: {token_to_string(tok)}")
        case tok.kind:
            Eof:
                this.at_end = true

                if not this.at_bol:
                    this.emit_token(kind: TokenKind.NewLine(), location: location_at(row: this.row, column: 1))

                # Dedent to top level!
                while this.indent_stack.len() > 1:
                    let tmp = this.indent_stack.pop_front()
                    this.emit_token(kind: TokenKind.Dedent(), location: location_at(row: this.row, column: 1))

            Space(x):
                if this.at_bol:
                    this.spaces += x
            NewLine:
                this.on_newline(tok)
            Comment(x):
                tok.kind = TokenKind.NewLine()
                this.on_newline(tok)
        else:
            if this.at_bol:
                this.at_bol = false
                if this.spaces > this.indent_stack.last():
                    # 1x indent!
                    this.indent_stack.append(this.spaces)

                    this.emit_token(kind: TokenKind.Indent(), location: tok.location)
                else:
                    while this.spaces < this.indent_stack.last():
                        # n times dedent!
                        let tmp = this.indent_stack.pop_last()
                        if tmp < this.spaces:
                            panic("Indentation error")
                        this.emit_token(kind: TokenKind.Dedent(), location: tok.location)

            # print("ehhh -> " + token_to_string(tok))
            this.emit(tok)

    fn on_newline(tok: Token):
        if not this.at_bol:
            this.emit(tok)
        this.at_bol = true
        this.spaces = 0
        this.row += 1
    
    fn emit(tok: Token):
        this.pending.append(tok)
    
    fn emit_token(kind: TokenKind, location: Location):
        this.emit(tok: Token(kind, location))

    fn next_token2() -> Token:
        let n = this.source_length
        if this.offset < n:
            # Start of new token:
            this.tok_begin = this.offset
            let kind = TokenKind.Error()
            let begin_column = this.tok_begin - this.col_start + this.start_col
            let begin = Position(row: this.row, column: begin_column)

            # Get char:
            let c = this.next_char()

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
                while this.match(txt: ' '):
                    pass
                kind = TokenKind.Space(amount: std.str_len(this.get_lexeme()))
            elif c == '#':
                # Line comment
                while this.offset < n and not is_lf(c: this.peek()):
                    this.offset += 1
                this.offset += 1
                kind = TokenKind.Comment(comment: this.get_lexeme())
                this.col_start = this.offset
            elif ord(c) == 34:
                while this.offset < n and not (ord(c: this.peek()) == 34):
                    this.offset += 1
                this.offset += 1
                # String
                let txt: str = this.get_lexeme()
                txt = str_slice(value: txt, begin: 1, end: str_len(txt) - 1)
                kind = TokenKind.String(txt)
            elif c == '-':
                if this.match(txt: '>'):
                    kind = TokenKind.Arrow()
                elif this.match(txt: '='):
                    kind = TokenKind.MinusEquals()
                else:
                    kind = TokenKind.Minus()
            elif c == '+':
                if this.match(txt: '='):
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
                this.col_start = this.offset
            elif is_digit(c):
                let is_hex = false
                if c == '0' and this.offset < n:
                    if this.peek() == 'x':
                        is_hex = true
                    elif this.peek() == 'X':
                        is_hex = true

                if is_hex:
                    this.offset += 1
                    # Hex number!
                    while this.offset < n and is_hex_digit(c: this.peek()):
                        this.offset += 1
                    let hextext = this.get_lexeme()
                    hextext = str_slice(value: hextext, begin: 2, end: str_len(hextext))
                    let int_value = hex_to_int(hextext)
                    kind = TokenKind.Integer(int_value)
                else:
                    while this.offset < n and is_digit(c: this.peek()):
                        this.offset += 1
                    if this.offset < n and this.peek() == '.':
                        # Floating point!
                        this.offset += 1
                        while this.offset < n and is_digit(c: this.peek()):
                            this.offset += 1
                        let val2 = this.get_lexeme()
                        let float_value: float = str_to_float(val2)
                        kind = TokenKind.Float(float_value)
                    else:
                        # Normal decimal number
                        let int_value: int = str_to_int(this.get_lexeme())
                        kind = TokenKind.Integer(int_value)
            elif is_id(c):
                while this.offset < n and is_id_or_digit(c: this.peek()):
                    this.offset += 1

                # Check for keywords:
                kind = check_keyword(txt: this.get_lexeme())

            elif ord(c) == 39:
                # Char literal
                this.offset += 2
                # TODO: check closing '
                let char_value = std.str_get(value: this.get_lexeme(), index: 1)
                kind = TokenKind.Char(char_value)

            elif c == '<':
                if this.match(txt: '='):
                    kind = TokenKind.LessEquals()
                else:
                    kind = TokenKind.Less()
            elif c == '>':
                if this.match(txt: '='):
                    kind = TokenKind.GreaterEquals()
                else:
                    kind = TokenKind.Greater()
            elif c == '=':
                if this.match(txt: '='):
                    kind = TokenKind.EqualsEquals()
                else:
                    kind = TokenKind.Equals()
            elif c == '!':
                if this.match(txt: '='):
                    kind = TokenKind.NotEquals()

            let end_column = this.offset - 1
            end_column = end_column - this.col_start + this.start_col
                
            let end = Position(row: this.row, column: end_column)
            let location = Location(begin, end)

            return Token(kind, location)
        else:
            return Token(kind: TokenKind.Eof(), location: location_at(row: this.row, column: 1))
    
    fn peek() -> char:
        let n = this.source_length
        if this.offset < n:
            let c = std.str_get(text: this.source, index: this.offset)
            return c
        else:
            panic("Peek beyond input")
    
    fn next_char() -> char:
        let n = this.source_length
        if this.offset < n:
            let c = std.str_get(text: this.source, index: this.offset)
            this.offset += 1
            return c
        else:
            panic("Next char beyond input")

    fn match(txt: char) -> bool:
        let n = this.source_length
        if this.offset < n:
            let c = std.str_get(text: this.source, index: this.offset)
            if c == txt:
                this.offset += 1
                return true
            else:
                return false
        else:
            return false
    
    fn get_lexeme() -> str:
        return std.str_slice(value: this.source, begin: this.tok_begin, end: this.offset)

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
