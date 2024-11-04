
from bytes import bytes_from_ascii, bytes_to_ascii, Bytes
from base64 import base64_encode, base64_decode
from std import print
from unittest import assert_str_equals


fn main() -> int:
    test_base64_example1()
    test_base64_example2()
    test_base64_padding()
    print("OK")
    0

fn test_base64_example1():
    let text = "Many hands make light work."
    let encoded_check = "TWFueSBoYW5kcyBtYWtlIGxpZ2h0IHdvcmsu"
    check_ascii_example(text, encoded_check)

fn test_base64_example2():
    let text = "Hello world!"
    let encoded_check = "SGVsbG8gd29ybGQh"
    check_ascii_example(text, encoded_check)

fn test_base64_padding():
    check_ascii_example(text: "A", encoded_check: "QQ==")
    check_ascii_example(text: "AB", encoded_check: "QUI=")
    check_ascii_example(text: "ABC", encoded_check: "QUJD")

fn check_ascii_example(text: str, encoded_check: str):
    # Check encoding / decoding roundtrip
    let data = bytes_from_ascii(text)
    let encoded = base64_encode(data)
    assert_str_equals(encoded, encoded_check)
    
    let decoded = bytes_to_ascii(data: base64_decode(text: encoded))
    assert_str_equals(text, decoded)
