

from std import print
from vectype import Vector, new_vector
from unittest import assert_int_equals


pub fn main() -> int:
    test_vector()
    print("OK")
    0


fn test_vector():
    let x: Vector[int] = new_vector()
    assert_int_equals(0, x.len())
    x.append(1)
    x.append(42)
    assert_int_equals(2, x.len())
    x.append(1337)
    assert_int_equals(1, x.get(index: 0))
    assert_int_equals(42, x.get(index: 1))
    assert_int_equals(1337, x.get(index: 2))
    assert_int_equals(3, x.len())

    x.append(43)
    x.append(1338)
    assert_int_equals(5, x.len())
    assert_int_equals(43, x.get(index: 3))
    assert_int_equals(1338, x.get(index: 4))
