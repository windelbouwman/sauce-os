
# Unit testing helper functions.

from utils import assert
from std import float_to_str
from math import fabs

pub fn assert_str_equals(a?: str, b?: str):
    assert(condition: a == b, message: "Expect '{a}' == '{b}'")

pub fn assert_int_equals(a?: int, b?: int):
    assert(condition: a == b, message: "Expect '{a}' == '{b}'")

pub fn assert_almost_equals(a?: float, b?: float):
    let diff = fabs(a - b)
    assert(condition: diff < 0.001, message: "Expect '{float_to_str(a)}' is nearly '{float_to_str(b)}'")

pub fn assert_true(condition?: bool):
    assert(condition, message: "Expected true, got false")

pub fn assert_false(condition?: bool):
    assert(condition: not condition, message: "Expected false, got true")

