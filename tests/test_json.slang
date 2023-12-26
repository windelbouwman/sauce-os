
from std import print, chr
from utils import panic
from json import parse_json, json_to_string, JsonException
from unittest import assert_str_equals, assert_int_equals, assert_true, assert_false


fn main() -> int:
    test_roundtrip()
    print("OK")
    return 0


fn test_roundtrip():
    let quote = chr(34)
    let left_brace = chr(123)
    let right_brace = chr(125)

    check_roundtrips("{left_brace} {quote}w00t{quote}: 1337 {right_brace}")
    check_roundtrips("{left_brace} {quote}w00t{quote}: 1337, {quote}A{quote}: 42 {right_brace}")
    check_roundtrips("{left_brace} {quote}no{quote}: false, {quote}yes{quote}: true, {quote}void{quote}: null {right_brace}")
    check_roundtrips("{left_brace} {quote}values{quote}: [ 1, 2, 3, 4 ] {right_brace}")

fn check_roundtrips(text?: str):
    try:
        let value = parse_json(text)
        let text2 = json_to_string(value)
        assert_str_equals(text, text2)
    except (e: JsonException):
        panic(e.message)
