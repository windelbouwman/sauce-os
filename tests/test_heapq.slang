
from std import print
from unittest import assert_str_equals, assert_int_equals, assert_true, assert_false
from heapq import PriorityQueue, new_priority_queue_with_capacity

fn cmp(a: int, b: int) -> bool:
    a < b

fn main() -> int:
    let q: PriorityQueue[int] = new_priority_queue_with_capacity(capacity: 10, f: cmp)
    assert_true(q.is_empty())

    q.push(5)
    assert_false(q.is_empty())
    let x = q.pop()
    assert_true(q.is_empty())
    assert_int_equals(5, x)

    q.push(6)
    q.push(100)
    q.push(99)
    q.push(95)
    q.push(98)
    q.push(7)
    q.push(8)
    q.push(3)
    assert_int_equals(3, q.pop())
    assert_int_equals(6, q.pop())
    assert_int_equals(7, q.pop())
    assert_int_equals(8, q.pop())
    assert_int_equals(95, q.pop())
    assert_int_equals(98, q.pop())
    assert_int_equals(99, q.pop())
    assert_int_equals(100, q.pop())
    assert_true(q.is_empty())

    print("OK")
    0
