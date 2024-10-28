
# json data serialization library

from utils import panic
from std import str_len, str_get, ord, str_slice
from std import read_file
from std import file_writeln, file_open, file_close
from strlib import str_join, is_digit, str_to_int
from datatypes import List, Option, option_is_some

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


fn write_json_to_file(filename: str, obj: JsonValue):
    let json_txt = json_to_string(obj)
    # print("JSON: {json_txt}")
    let handle = file_open(filename, mode: "w")
    file_writeln(handle, line: json_txt)
    file_close(handle)

fn read_json_from_file(filename: str) -> JsonValue except JsonException:
    let text = read_file(filename)
    parse_json(text)


pub fn parse_json(text: str) -> JsonValue except JsonException:
    let lexer = Lexer(text)
    lexer.init()
    let parser = Parser(lexer)
    parser.parse_value()

pub fn json_to_string(value?: JsonValue) -> str:
    case value:
        Integer(value):
            "{value}"
        Bool(value):
            if value:
                "true"
            else:
                "false"
        String(text):
            "\"{text}\""
        Object(items):
            let parts: List[str] = List()
            for item in items:
                parts.append("\"{item.key}\": {json_to_string(item.value)}")
            let txt = str_join(parts, sep: ", ")
            "\{ {txt} \}"
        Array(values):
            let parts: List[str] = List()
            for value in values:
                parts.append(json_to_string(value))
            let txt = str_join(parts, sep: ", ")
            "[ {txt} ]"
        Null:
            "null"

struct JsonException:
    message: str
    pos: int


class JsonBrowser:
    # A helper class to help navigate JSON structures.
    var m_value: JsonValue = JsonValue.Null()
    var m_stack: List[JsonValue] = List()

    fn push_value(value: JsonValue):
        m_stack.append(m_value)
        m_value = value

    fn pop_value():
        m_value = m_stack.pop_last()

    fn get_attribute(attr: str) -> JsonValue:
        case m_value:
            Object(items):
                for item in items:
                    if item.key == attr:
                        return item.value
                panic("No attribute: {attr}")
        else:
            panic("Not a JSON object")

    fn has_attribute(attr: str) -> bool:
        option_is_some(find_attribute(attr))

    fn find_attribute(attr: str) -> Option[JsonValue]:
        case m_value:
            Object(items):
                for item in items:
                    if item.key == attr:
                        return Option.Some(item.value)
                return Option.None()
        else:
            panic("Not a JSON object")

    fn get_array_values() -> List[JsonValue]:
        case m_value:
            Array(values):
                values
        else:
            panic("Not a JSON array")

    fn get_array_attribute(attr: str) -> List[JsonValue]:
        enter_attribute(attr)
        let values = get_array_values()
        pop_value()
        values

    fn get_text_attribute(attr: str) -> str:
        enter_attribute(attr)
        let text = get_text()
        pop_value()
        text

    fn get_integer_attribute(attr: str) -> int:
        enter_attribute(attr)
        let value = get_integer()
        pop_value()
        value

    fn get_boolean_attribute(attr: str) -> bool:
        enter_attribute(attr)
        let value = get_boolean()
        pop_value()
        value

    fn get_text() -> str:
        # Get text from current node
        case m_value:
            String(text):
                text
        else:
            panic("Not a JSON text")

    fn get_integer() -> int:
        # Get integer from current node
        case m_value:
            Integer(value):
                value
        else:
            panic("Not a JSON integer")

    fn get_boolean() -> bool:
        # Get boolean from current node
        case m_value:
            Bool(value):
                value
        else:
            panic("Not a JSON bool")

    fn enter_attribute(attr: str):
        push_value(value: get_attribute(attr))

class JsonBuilder:
    var m_object_stack: List[JsonObjectBuilder] = List()
    var m_array_stack: List[JsonArrayBuilder] = List()

    fn begin_object():
        m_object_stack.append(JsonObjectBuilder())
    
    fn add_attribute(attr: str, value: JsonValue):
        m_object_stack.last().add_attribute(attr, value)

    fn add_boolean_attribute(attr: str, value: bool):
        add_attribute(attr, value: JsonValue.Bool(value))

    fn add_text_attribute(attr: str, text: str):
        add_attribute(attr, value: JsonValue.String(text))

    fn add_text_as_element(text: str):
        add_element(value: JsonValue.String(text))

    fn add_integer_attribute(attr: str, value: int):
        add_attribute(attr, value: JsonValue.Integer(value))

    fn end_object() -> JsonValue:
        let builder = m_object_stack.pop_last()
        builder.finish()

    fn end_object_as_element():
        # Complete object creation, and append to current array
        let value = end_object()
        add_element(value)

    fn end_object_as_attribute(attr: str):
        # Complete object creation, and append to current array
        let value = end_object()
        add_attribute(attr, value)

    fn begin_array():
        m_array_stack.append(JsonArrayBuilder())

    fn add_element(value: JsonValue):
        m_array_stack.last().add_element(value)

    fn end_array() -> JsonValue:
        let builder = m_array_stack.pop_last()
        builder.finish()

    fn end_array_as_attribute(attr: str):
        let array_obj = end_array()
        add_attribute(attr, value: array_obj)


class JsonObjectBuilder:
    var m_attributes: List[KeyValue] = List()

    fn add_attribute(attr: str, value: JsonValue):
        m_attributes.append(KeyValue(key: attr, value))

    fn finish() -> JsonValue:
        JsonValue.Object(m_attributes)


class JsonArrayBuilder:
    var m_values: List[JsonValue] = List()

    fn add_element(value: JsonValue):
        m_values.append(value)

    fn finish() -> JsonValue:
        JsonValue.Array(m_values)

class Parser:
    var m_buffer: List[JsonToken] = List()
    var lexer : Lexer

    fn parse_value() -> JsonValue except JsonException:
        let token = get_token()
        case token.kind:
            BracketLeft:
                parse_array()
            BraceLeft:
                parse_object()
            Integer(value):
                JsonValue.Integer(value)
            String(text):
                JsonValue.String(text)
            Id(text):
                if text == "true":
                    JsonValue.Bool(true)
                elif text == "false":
                    JsonValue.Bool(false)
                elif text == "null":
                    JsonValue.Null()
                else:
                    raise JsonException(message: "Invalid id: {text}", pos: token.pos)
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
            case token.kind:
                Comma:
                    pass
                BraceRight:
                    break
            else:
                raise unexpected(token, expected: ", or ]")
        JsonValue.Object(items)

    fn parse_array() -> JsonValue except JsonException:
        let values: List[JsonValue] = List()
        # Check for empty array:
        let token = get_token()
        case token.kind:
            BracketRight:
                pass
        else:
            unget_token(token)
            loop:
                let value = parse_value()
                values.append(value)

                let token = get_token()
                case token.kind:
                    Comma:
                        pass
                    BracketRight:
                        break
                else:
                    raise unexpected(token, expected: ", or ]")

        JsonValue.Array(values)
    
    fn parse_string() -> str except JsonException:
        let token = get_token()
        case token.kind:
            String(value):
                value
        else:
            raise unexpected(token, expected: ":")

    fn parse_colon() except JsonException:
        let token = get_token()
        case token.kind:
            Colon:
                pass
        else:
            raise unexpected(token, expected: ":")

    fn get_token() -> JsonToken:
        if m_buffer.is_empty():
            lexer.lex()
        else:
            m_buffer.pop_front()

    fn unget_token(token: JsonToken):
        m_buffer.prepend(token)
    
    fn unexpected(token: JsonToken, expected: str) -> JsonException:
        JsonException(message: "Unexpected token {token_to_str(token)}, expected {expected}", pos: token.pos)

struct JsonToken:
    kind: JsonTokenKind
    pos: int

enum JsonTokenKind:
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
    UnexpectedEof
    Error(c: char)

fn token_to_str(token: JsonToken) -> str:
    case token.kind:
        BracketLeft:
            "BracketLeft"
        BracketRight:
            "BracketRight"
        BraceLeft:
            "BraceLeft"
        BraceRight:
            "BraceRight"
        Comma:
            "Comma"
        Colon:
            "Colon"
        Integer(value):
            "Integer({value})"
        String(text):
            "String({text})"
        Id(text):
            "Id({text})"
        Eof:
            "Eof"
        UnexpectedEof:
            "UnexpectedEof"
        Error(c):
            "Error({ord(c)})"

class Lexer:
    var text: str
    var index: int = 0
    var n: int = 0

    fn init():
        index = 0
        n = str_len(text)

    fn lex() -> JsonToken:
        loop:
            let begin = index
            let c = str_get(text, index)
            index += 1
            if is_id(c):
                while is_id(c: str_get(text, index)):
                    index += 1
                    if index >= n:
                        break
                let end = index
                let slice = str_slice(text, begin, end)
                return create_token(JsonTokenKind.Id(slice))
            elif c == ',':
                return create_token(JsonTokenKind.Comma())
            elif c == ':':
                return create_token(JsonTokenKind.Colon())
            elif c == '[':
                return create_token(JsonTokenKind.BracketLeft())
            elif c == ']':
                return create_token(JsonTokenKind.BracketRight())
            elif c == '{':
                return create_token(JsonTokenKind.BraceLeft())
            elif c == '}':
                return create_token(JsonTokenKind.BraceRight())
            elif c == '"':
                loop:
                    c = str_get(text, index)
                    index += 1
                    if c == '"':
                        break
                    if index >= n:
                        return create_token(JsonTokenKind.UnexpectedEof())
                let end = index
                begin += 1
                end -= 1
                let slice = str_slice(text, begin, end)
                return create_token(JsonTokenKind.String(slice))
            elif is_digit(c):
                while is_digit(c: str_get(text, index)):
                    index += 1
                    if index >= n:
                        break
                let end = index
                let slice = str_slice(text, begin, end)
                return create_token(JsonTokenKind.Integer(str_to_int(slice)))
            elif c == ' ':
                pass
            elif ord(c) == 13 or ord(c) == 10:
                pass
            else:
                return create_token(JsonTokenKind.Error(c))
        panic("Unreachable")
    
    fn create_token(kind?: JsonTokenKind) -> JsonToken:
        JsonToken(kind, pos: index)

fn is_id(c: char) -> bool:
    let o = ord(c)
    if (o >= 97) and (o <= 122):
        true
    else:
        false

