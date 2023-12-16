
from std import print
from math import modulo
from unittest import assert_int_equals

fn main() -> int:
    test_modulo()
    print("OK")
    return 0

fn test_modulo():
    assert_int_equals(modulo(value: 9, divisor: 5), 4)
    assert_int_equals(modulo(value: 6, divisor: 5), 1)
    assert_int_equals(modulo(value: 10, divisor: 5), 0)
    assert_int_equals(modulo(value: 11, divisor: 2), 1)
    assert_int_equals(modulo(value: 8, divisor: 2), 0)
