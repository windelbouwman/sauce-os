
from std import print
from utils import panic
from json import parse_json, json_to_string, JsonException
from unittest import assert_str_equals, assert_int_equals, assert_true, assert_false


fn main() -> int:
    test_roundtrip()
    print("OK")
    return 0


fn test_roundtrip():
    check_roundtrips("\{ \"w00t\": 1337 \}")
    check_roundtrips("\{ \"w00t\": 1337, \"A\": 42 \}")
    check_roundtrips("\{ \"no\": false, \"yes\": true, \"void\": null \}")
    check_roundtrips("\{ \"values\": [ 1, 2, 3, 4 ] \}")

fn check_roundtrips(text?: str):
    try:
        let value = parse_json(text)
        let text2 = json_to_string(value)
        assert_str_equals(text, text2)
    except (e: JsonException):
        panic(e.message)
