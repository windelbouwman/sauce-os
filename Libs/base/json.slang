
# json data serialization library

from utils import panic
from std import str_len, str_get, ord, chr, str_slice, str_to_int
from strlib import str_join, is_digit
from datatypes import List

enum JsonValue:
    Integer(value: int)
    String(text: str)
    Bool(value: bool)
    Object(items: List[KeyValue])
    Array(values: List[JsonValue])
    Null

struct KeyValue:
    key: str
    value: JsonValue

pub fn parse_json(text: str) -> JsonValue except JsonException:
    let lexer = Lexer(text)
    lexer.init()
    let parser = Parser(lexer)
    return parser.parse_value()

pub fn json_to_string(value?: JsonValue) -> str:
    case value:
        Integer(value):
            return "{value}"
        Bool(value):
            if value:
                return "true"
            else:
                return "false"
        String(text):
            return "{chr(34)}{text}{chr(34)}"
        Object(items):
            let parts: List[str] = List()
            for item in items:
                parts.append("{chr(34)}{item.key}{chr(34)}: {json_to_string(item.value)}")
            let txt = str_join(parts, sep: ", ")
            return "{chr(123)} {txt} {chr(125)}"
        Array(values):
            let parts: List[str] = List()
            for value in values:
                parts.append(json_to_string(value))
            let txt = str_join(parts, sep: ", ")
            return "[ {txt} ]"
        Null:
            return "null"


struct JsonException:
    message: str

class Parser:
    var buffer: List[JsonToken] = List()
    var lexer : Lexer

    fn parse_value() -> JsonValue except JsonException:
        let token = get_token()
        case token:
            BracketLeft:
                return parse_array()
            BraceLeft:
                return parse_object()
            Integer(value):
                return JsonValue.Integer(value)
            String(text):
                return JsonValue.String(text)
            Id(text):
                if text == "true":
                    return JsonValue.Bool(true)
                elif text == "false":
                    return JsonValue.Bool(false)
                elif text == "null":
                    return JsonValue.Null()
                else:
                    raise JsonException(message: "Invalid id: {text}")
        else:
            raise unexpected(token, expected: "[ or number")

    fn parse_object() -> JsonValue except JsonException:
        let items: List[KeyValue] = List()
        loop:
            let key = parse_string()
            parse_colon()
            let value = parse_value()
            items.append(KeyValue(key, value))
            
            let token = get_token()
            case token:
                Comma:
                    pass
                BraceRight:
                    break
            else:
                raise unexpected(token, expected: ", or ]")
        return JsonValue.Object(items)

    fn parse_array() -> JsonValue except JsonException:
        let values: List[JsonValue] = List()
        loop:
            let value = parse_value()
            values.append(value)

            let token = get_token()
            case token:
                Comma:
                    pass
                BracketRight:
                    break
            else:
                raise unexpected(token, expected: ", or ]")

        return JsonValue.Array(values)
    
    fn parse_string() -> str except JsonException:
        let token = get_token()
        case token:
            String(value):
                return value
        else:
            raise unexpected(token, expected: ":")

    fn parse_colon() except JsonException:
        let token = get_token()
        case token:
            Colon:
                pass
        else:
            raise unexpected(token, expected: ":")

    fn get_token() -> JsonToken:
        return lexer.lex()
    
    fn unexpected(token: JsonToken, expected: str) -> JsonException:
        return JsonException(message: "Unexpected token, expected {expected}")

enum JsonToken:
    BracketLeft
    BracketRight
    BraceLeft
    BraceRight
    Comma
    Colon
    Integer(value: int)
    String(text: str)
    Id(text: str)
    Eof
    Error

class Lexer:
    var text: str
    var index: int = 0
    var n: int = 0

    fn init():
        index = 0
        n = str_len(text)

    fn lex() -> JsonToken:
        let quote = chr(34)
        loop:
            let begin = index
            let c = str_get(text, index)
            index += 1
            if c == ',':
                return JsonToken.Comma()
            elif c == ':':
                return JsonToken.Colon()
            elif c == '[':
                return JsonToken.BracketLeft()
            elif c == ']':
                return JsonToken.BracketRight()
            elif c == '{':
                return JsonToken.BraceLeft()
            elif c == '}':
                return JsonToken.BraceRight()
            elif c == quote:
                loop:
                    c = str_get(text, index)
                    index += 1
                    if c == quote:
                        break
                    if index >= n:
                        return JsonToken.Error()
                let end = index
                begin += 1
                end -= 1
                let slice = str_slice(text, begin, end)
                return JsonToken.String(slice)
            elif is_digit(c):
                while is_digit(c: str_get(text, index)):
                    index += 1
                    if index >= n:
                        break
                let end = index
                let slice = str_slice(text, begin, end)
                return JsonToken.Integer(str_to_int(slice))
            elif is_id(c):
                while is_id(c: str_get(text, index)):
                    index += 1
                    if index >= n:
                        break
                let end = index
                let slice = str_slice(text, begin, end)
                return JsonToken.Id(slice)
            elif c == ' ':
                pass
            else:
                return JsonToken.Error()
        panic("Unreachable")

fn is_id(c: char) -> bool:
    let o = ord(c)
    if (o >= 97) and (o <= 122):
        return true
    else:
        return false

