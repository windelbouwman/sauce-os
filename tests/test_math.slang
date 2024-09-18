
from std import print, float_to_str, float_to_str2
from utils import assert
from math import modulo, fabs, floor, ceil, factorial, sin, cos
from unittest import assert_int_equals

fn main() -> int:
    test_modulo()
    test_factorial()
    test_floor_ceil()
    test_trigoniometrics()
    print("OK")
    return 0

fn test_modulo():
    assert_int_equals(modulo(value: 9, divisor: 5), 4)
    assert_int_equals(modulo(value: 6, divisor: 5), 1)
    assert_int_equals(modulo(value: 10, divisor: 5), 0)
    assert_int_equals(modulo(value: 11, divisor: 2), 1)
    assert_int_equals(modulo(value: 8, divisor: 2), 0)

fn test_factorial():
    assert_int_equals(factorial(0), 1)
    assert_int_equals(factorial(1), 1)
    assert_int_equals(factorial(2), 2)
    assert_int_equals(factorial(3), 6)
    assert_int_equals(factorial(4), 24)
    assert_int_equals(factorial(5), 120)

fn test_trigoniometrics():
    let x = 0.0
    while x < 10:
        # print("x={float_to_str(x)} sin(x)={float_to_str2(value: sin(x), digits: 20)} cos(x)={float_to_str2(value: cos(x), digits: 20)}")
        x += 0.1

    let pi = 3.1415926535897932384626433
    assert_are_close(sin(0), 0)
    assert_are_close(sin(0.5 * pi), 1)
    assert_are_close(sin(pi), 0)
    assert_are_close(sin(1.5 * pi), -1)
    assert_are_close(sin(2 * pi), 0)
    assert_are_close(sin(2), 0.9092974268256817)

    assert_are_close(cos(0), 1)
    assert_are_close(cos(0.5 * pi), 0)
    assert_are_close(cos(pi), -1)
    assert_are_close(cos(1.5 * pi), 0)
    assert_are_close(cos(2 * pi), 1)

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
    let eps = 0.000000000000001  # A small margin
    assert(condition: diff < eps, message: "{float_to_str2(value: a, digits: 20)} is not close to {float_to_str2(value: b, digits: 20)} diff={float_to_str2(value: diff, digits: 20)} eps={float_to_str2(value: eps, digits: 20)}")
