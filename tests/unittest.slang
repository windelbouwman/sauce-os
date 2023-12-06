
# Unit testing helper functions.

from utils import assert

pub fn assert_str_equals(a?: str, b?: str):
    assert(condition: a == b, message: "Expect '{a}' == '{b}'")

pub fn assert_int_equals(a?: int, b?: int):
    assert(condition: a == b, message: "Expect '{a}' == '{b}'")
