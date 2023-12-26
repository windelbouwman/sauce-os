

from std import print
from datatypes import Set
from unittest import assert_str_equals, assert_int_equals, assert_true, assert_false


fn main() -> int:
    test_set()
    print("OK")
    return 0


fn test_set():
    let x = Set()
    assert_true(x.is_empty())
    x.add("one")
    x.add("two")
    x.add("two")
    assert_false(x.is_empty())
    assert_true(x.contains("one"))
    assert_false(x.contains("three"))
    x.remove("two")
    assert_false(x.is_empty())
    assert_false(x.contains("two"))
    x.remove("one")
    assert_true(x.is_empty())
    x.remove("one")

