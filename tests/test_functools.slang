
from datatypes import List, vec4
from functools import sum_integers
from unittest import assert_int_equals

fn main() -> int:
    test_sum()
    return 0

fn test_sum():
    let values = vec4(1, 2, 3, 4)
    let s = sum_integers(values)
    assert_int_equals(s, 10)
