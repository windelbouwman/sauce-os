
# Idea for an assembler

from std import str_len
from utils import unimplemented
from strlib import split_lines
from datatypes import List

pub class Assembler:
    var m_line_parser: LineParser = LineParser()

    fn assemble(source: str):
        let lines = split_lines(text: source)
        for line in lines:
            let result = m_line_parser.parse_line(line)

struct ParsedLine:
    mnemonic: str
    arguments: List[str]

class LineParser:
    var m_tokenizer: Tokenizer = Tokenizer()

    fn parse_line(line: str) -> ParsedLine:
        # Parse a single line 
        m_tokenizer.set_line(line)

        let tok = next_token()
        case tok.kind:
            Id(value):
                pass
            Comment(text):
                # empty line with only comments
                pass
                unimplemented("comment")
            End:
                # empty line
                pass
                unimplemented("empty")
        else:
            unexpected(tok, expected: "id, comment or empty line")
        
        unimplemented("parse_line")
    
    fn unexpected(tok: Token, expected: str):
        error("Got {tok}, expected: {expected}")

    fn error(message?: str):
        pass
    
    fn next_token() -> Token:
        m_tokenizer.next_token()

class Tokenizer:
    var m_index: int = 0
    var m_size: int = 0
    var m_line: str = ""

    fn set_line(line: str):
        m_line = line
        m_size = str_len(text: line)
        m_index = 0

    fn next_token() -> Token:
        if m_index < m_size:
            unimplemented("next_token")
        else:
            let kind = TokenKind.End()
            Token(kind)

class Token:
    var kind: TokenKind
    var pos: int = 0

    fn to_string() -> str:
        "T"
    
enum TokenKind:
    Id(value: str)
    Number(value: int)
    String(value: str)
    Colon
    Comma
    Comment(text: str)
    End
