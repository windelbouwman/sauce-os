
# Unit testing helper functions.

from utils import assert
from datatypes import List, option_unwrap
from std import float_to_str
from math import fabs
from bytes import Bytes
# from functools import pairs

pub fn assert_str_equals(a?: str, b?: str):
    assert(condition: a == b, message: "'{a}' is not equal to '{b}'")

pub fn assert_int_equals(a?: int, b?: int):
    assert(condition: a == b, message: "Expect '{a}' == '{b}'")

pub fn assert_almost_equals(a?: float, b?: float):
    let diff = fabs(a - b)
    assert(condition: diff < 0.001, message: "Expect '{float_to_str(a)}' is nearly '{float_to_str(b)}'")

fn assert_list_equals(a?: List[str], b?: List[str]):
    assert(condition: a.len() == b.len(), message: "Expect equal long lists {a.len()} != {b.len()}")

    # TODO: make below work:
    # for pair in pairs(a, b):
    # ...

    # Check parts!
    let i = a.iter()
    let j = b.iter()
    loop:
        case i.next():
            Some(ii):
                let jj = option_unwrap(j.next())
                assert_str_equals(ii, jj)
            None:
                break

fn assert_bytes_equals(a?: Bytes, b?: Bytes):
    let a_hex = a.as_hex()
    let b_hex = b.as_hex()
    assert_str_equals(a_hex, b_hex)

pub fn assert_true(condition?: bool):
    assert(condition, message: "Expected true, got false")

pub fn assert_false(condition?: bool):
    assert(condition: not condition, message: "Expected false, got true")

