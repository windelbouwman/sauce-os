

from std import print
from deque import Queue, new_queue
from unittest import assert_str_equals, assert_int_equals, assert_true


fn main() -> int:
    test_queue()
    print("OK")
    0


fn test_queue():
    let x: Queue[int] = new_queue(capacity: 2)
    assert_int_equals(0, x.len())
    x.push(1)
    assert_int_equals(1, x.len())
    x.push(42)
    assert_int_equals(2, x.len())
    x.push(1337)
    assert_int_equals(3, x.len())

    assert_int_equals(1, x.pop())
    assert_int_equals(2, x.len())

    assert_int_equals(42, x.pop())
    assert_int_equals(1, x.len())

    assert_int_equals(1337, x.pop())
    assert_int_equals(0, x.len())
    
