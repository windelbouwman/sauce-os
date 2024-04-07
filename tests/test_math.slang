
from std import print, float_to_str
from utils import assert
from math import modulo, fabs, floor, ceil
from unittest import assert_int_equals

fn main() -> int:
    test_modulo()
    test_floor_ceil()
    print("OK")
    return 0

fn test_modulo():
    assert_int_equals(modulo(value: 9, divisor: 5), 4)
    assert_int_equals(modulo(value: 6, divisor: 5), 1)
    assert_int_equals(modulo(value: 10, divisor: 5), 0)
    assert_int_equals(modulo(value: 11, divisor: 2), 1)
    assert_int_equals(modulo(value: 8, divisor: 2), 0)

fn test_floor_ceil():
    assert_are_close(2.0, floor(2.0))
    assert_are_close(2.0, ceil(2.0))

    assert_are_close(2.0, floor(2.0001))
    assert_are_close(3.0, ceil(2.0001))

    assert_are_close(2.0, floor(2.999))
    assert_are_close(3.0, ceil(2.999))

    assert_are_close(-3.0, floor(-2.7))
    assert_are_close(-2.0, ceil(-2.7))

    # TODO: check whole negative numbers?
    #assert_are_close(-2.0, floor(-2.0))
    #assert_are_close(-2.0, ceil(-2.0))

fn assert_are_close(a?: float, b?: float):
    let diff = fabs(a - b)
    let eps = 0.000001  # A small margin
    assert(condition: diff < eps, message: "{float_to_str(a)} is not close to {float_to_str(b)}")
