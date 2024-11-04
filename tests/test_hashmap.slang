
from std import print
from unittest import assert_int_equals
from hashmap import HashMap

fn main() -> int:
    test_hash_examples()
    print("OK")
    0

fn test_hash_examples():
    let m = HashMap()
    m.insert(key: "printf", value: 1)
    m.insert(key: "putc", value: 2)
    m.insert(key: "open", value: 3)
    m.insert(key: "close", value: 4)
    m.insert(key: "write", value: 5)
    m.insert(key: "read", value: 6)

    assert_int_equals(m.get(key: "printf"), 1)
    assert_int_equals(m.get(key: "putc"), 2)
    assert_int_equals(m.get(key: "open"), 3)
    assert_int_equals(m.get(key: "close"), 4)
    assert_int_equals(m.get(key: "write"), 5)
    assert_int_equals(m.get(key: "read"), 6)

    assert_int_equals(m.len(), 6)

    # Test iteration over hashmap:
    for x in m:
        print("x = {x}")

