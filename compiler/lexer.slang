# Turn source text into a sequence of tokens

import std
from std import print, ord
from token import Token, TokenKind, new_token, token_to_string
from location import Location, new_location
from datatypes import List, Option, Integer, new_integer


class Lexer:
    var pending: List[Token] = List()
    var indent_stack: List[Integer] = List()  # TODO: list of integers! (can only make list of non-basic types..)
    var at_bol: bool = true  # at begin-of-line (bol)
    var at_end: bool = false
    var spaces: int = 0
    var source: str = ""

    var tok_begin: int = 0
    var offset: int = 0
    var row: int = 1
    var col_start: int = 0

    fn init(source: str):
        this.source = source
        this.at_end = false
        this.at_bol = true
        this.row = 1
        this.indent_stack.append(new_integer(0))

    fn next_token() -> Token:
        while this.pending.is_empty() and not this.at_end:
            this.work_some()
        
        if this.pending.is_empty():
            return new_token(TokenKind::Eof(), new_location(this.row, 1))
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
                    this.emit(new_token(TokenKind::NewLine(), new_location(this.row, 1)))

                # Dedent to top level!
                while this.indent_stack.len() > 1:
                    let tmp = this.indent_stack.pop_front()
                    this.emit(new_token(TokenKind::Dedent(), new_location(this.row, 1)))

            Space(x):
                if this.at_bol:
                    this.spaces += x
            NewLine:
                this.on_newline(tok)
            Comment(x):
                tok.kind = TokenKind::NewLine()
                this.on_newline(tok)
        else:
            if this.at_bol:
                this.at_bol = false
                if this.spaces > this.indent_stack.last().value:
                    # 1x indent!
                    this.indent_stack.append(new_integer(this.spaces))

                    this.emit(new_token(TokenKind::Indent(), tok.location))
                else:
                    while this.spaces < this.indent_stack.last().value:
                        # n times dedent!
                        let tmp = this.indent_stack.pop_last().value
                        if tmp < this.spaces:
                            print("Indentation error")
                        this.emit(new_token(TokenKind::Dedent(), tok.location))

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

    fn next_token2() -> Token:
        let n = std.str_len(this.source)
        if this.offset < n:
            # Start of new token:
            this.tok_begin = this.offset
            let kind = TokenKind::Error()
            let column = this.tok_begin - this.col_start + 1
            let location = new_location(this.row, column)

            # Get char:
            let c = std.str_get(this.source, this.offset)
            this.offset += 1

            # Decide what to do based on char:
            if c == "(":
                kind = TokenKind::BraceOpen()
            elif c == ")":
                kind = TokenKind::BraceClose()
            elif c == "[":
                kind = TokenKind::BracketOpen()
            elif c == "]":
                kind = TokenKind::BracketClose()
            elif c == ",":
                kind = TokenKind::Comma()
            elif c == ".":
                kind = TokenKind::Dot()
            elif c == ":":
                if this.match(":"):
                    kind = TokenKind::Dot()
                else:
                    kind = TokenKind::Colon()
            elif c == " ":
                while this.match(" "):
                    pass
                kind = TokenKind::Space(std.str_len(this.get_lexeme()))
            elif c == "#":
                # Line comment
                while not is_lf(this.peek()) and this.offset < n:
                    this.offset += 1
                this.offset += 1
                kind = TokenKind::Comment(this.get_lexeme())
                this.col_start = this.offset
            elif ord(c) == 34:
                while not (ord(this.peek()) == 34) and this.offset < n:
                    this.offset += 1
                this.offset += 1
                # String
                kind = TokenKind::String(this.get_lexeme())
            elif c == "-":
                if this.match(">"):
                    kind = TokenKind::Arrow()
                elif this.match("="):
                    kind = TokenKind::MinusEquals()
                else:
                    kind = TokenKind::Minus()
            elif c == "+":
                if this.match("="):
                    kind = TokenKind::PlusEquals()
                else:
                    kind = TokenKind::Plus()
            elif c == "/":
                kind = TokenKind::Slash()
            elif c == "*":
                kind = TokenKind::Asterix()
            elif is_lf(c):
                kind = TokenKind::NewLine()
                this.col_start = this.offset
            elif is_digit(c):
                while is_digit(this.peek()):
                    this.offset += 1
                if this.peek() == ".":
                    # Floating point!
                    this.offset += 1
                    while is_digit(this.peek()):
                        this.offset += 1
                    # TODO: str to float
                    let val2 = this.get_lexeme()
                    let val: float = 3.14
                    kind = TokenKind::Float(val)
                else:
                    kind = TokenKind::Integer(std.str_to_int(this.get_lexeme()))
            elif is_id(c):
                while is_id_or_digit(this.peek()):
                    this.offset += 1

                # Check for keywords:
                kind = check_keyword(this.get_lexeme())
            elif c == "<":
                if this.match("="):
                    kind = TokenKind::LessEquals()
                else:
                    kind = TokenKind::Less()
            elif c == ">":
                if this.match("="):
                    kind = TokenKind::GreaterEquals()
                else:
                    kind = TokenKind::Greater()
            elif c == "=":
                if this.match("="):
                    kind = TokenKind::EqualsEquals()
                else:
                    kind = TokenKind::Equals()

            return new_token(kind, location)
        else:
            return new_token(TokenKind::Eof(), new_location(this.row, 1))
    
    fn peek() -> str:
        let n = std.str_len(this.source)
        if this.offset < n:
            let c = std.str_get(this.source, this.offset)
            return c
        else:
            return ""

    fn match(txt: str) -> bool:
        let n = std.str_len(this.source)
        if this.offset < n:
            let c = std.str_get(this.source, this.offset)
            if c == txt:
                this.offset += 1
                return true
            else:
                return false
        else:
            return false
    
    fn get_lexeme() -> str:
        return std.str_slice(this.source, this.tok_begin, this.offset)

fn is_lf(c: str) -> bool:
    let o = ord(c)
    return o == 10

fn is_digit(c: str) -> bool:
    # Check if a character is a digit.
    let o = ord(c)
    return (o >= 48) and (o <= 57)

fn is_id(c: str) -> bool:
    let o = ord(c)
    if (o >= 65) and (o <= 90):
        return true
    elif (o >= 97) and (o <= 122):
        return true
    elif c == "_":
        return true
    else:
        return false

fn is_id_or_digit(c: str) -> bool:
    return is_id(c) or is_digit(c)

fn check_keyword(txt: str) -> TokenKind:
    let kind = TokenKind::Identifier(txt)
    if txt == "and":
        kind = TokenKind::KwAnd()
    elif txt == "break":
        kind = TokenKind::KwBreak()
    elif txt == "case":
        kind = TokenKind::KwCase()
    elif txt == "class":
        kind = TokenKind::KwClass()
    elif txt == "continue":
        kind = TokenKind::KwContinue()
    elif txt == "else":
        kind = TokenKind::KwElse()
    elif txt == "elif":
        kind = TokenKind::KwElif()
    elif txt == "enum":
        kind = TokenKind::KwEnum()
    elif txt == "fn":
        kind = TokenKind::KwFn()
    elif txt == "for":
        kind = TokenKind::KwFor()
    elif txt == "from":
        kind = TokenKind::KwFrom()
    elif txt == "if":
        kind = TokenKind::KwIf()
    elif txt == "import":
        kind = TokenKind::KwImport()
    elif txt == "in":
        kind = TokenKind::KwIn()
    elif txt == "let":
        kind = TokenKind::KwLet()
    elif txt == "loop":
        kind = TokenKind::KwLoop()
    elif txt == "or":
        kind = TokenKind::KwOr()
    elif txt == "pass":
        kind = TokenKind::KwPass()
    elif txt == "return":
        kind = TokenKind::KwReturn()
    elif txt == "struct":
        kind = TokenKind::KwStruct()
    elif txt == "switch":
        kind = TokenKind::KwSwitch()
    elif txt == "var":
        kind = TokenKind::KwVar()
    elif txt == "while":
        kind = TokenKind::KwWhile()

    return kind
