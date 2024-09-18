
# Unit tests for strlib

from std import print, str_to_int, float_to_str2
from strlib import trim, hex_to_int, bin_to_int, find_char, is_digit
from strlib import int_to_hex_string
from datatypes import option_unwrap
from unittest import assert_str_equals, assert_int_equals
from utils import assert

fn main() -> int:
    test_trim()
    test_hex_to_int()
    test_bin_to_int()
    test_find_char()
    test_int_to_str()
    test_float_to_str()
    print("OK")
    return 0

fn test_trim():
    assert_str_equals(trim(" bla "), "bla")
    assert_str_equals(trim("bla  "), "bla")
    assert_str_equals(trim("   bla"), "bla")
    assert_str_equals(trim("   bla    "), "bla")
    assert_str_equals(trim("       "), "")

fn test_hex_to_int():
    assert_int_equals(hex_to_int(hextext: "AABB"), 0xAABB)
    assert_int_equals(hex_to_int(hextext: "123456"), 0x123456)
    assert_str_equals(int_to_hex_string(0xAABB), "0000AABB")
    assert_str_equals(int_to_hex_string(0x123456), "00123456")

fn test_bin_to_int():
    assert_int_equals(bin_to_int(bintext: "101"), 5)
    assert_int_equals(bin_to_int(bintext: "1100"), 12)
    assert_int_equals(0b101, 5)
    assert_int_equals(0b1100, 12)

fn test_float_to_str():
    let value = 3.14159265
    assert_str_equals(float_to_str2(value, digits: 0), "3")
    assert_str_equals(float_to_str2(value, digits: 1), "3.1")
    assert_str_equals(float_to_str2(value, digits: 2), "3.14")
    assert_str_equals(float_to_str2(value, digits: 3), "3.142")

fn test_find_char():
    let index = option_unwrap(find_char(text: "blaat5", criterium: is_digit))
    assert_int_equals(index, 5)

fn test_int_to_str():
    # Check a large number
    let large_number = "2906422699"
    let value = str_to_int(large_number)
    assert_int_equals(2906422699, value)
    let text = str(value)
    assert_str_equals("2906422699", text)
