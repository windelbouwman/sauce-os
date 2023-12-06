

from std import print
from datatypes import List
from unittest import assert_str_equals, assert_int_equals


fn main() -> int:
    test_list()
    print("OK")
    return 0


fn test_list():
    let x = List()
    assert_int_equals(0, x.len())
    x.append(1)
    x.append(42)
    assert_int_equals(2, x.len())
    x.append(1337)
    assert_int_equals(1, x.first())
    assert_int_equals(1, x.get(index: 0))
    assert_int_equals(42, x.get(index: 1))
    assert_int_equals(1337, x.get(index: 2))
    assert_int_equals(1337, x.last())
    assert_int_equals(3, x.len())
