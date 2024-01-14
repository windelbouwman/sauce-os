
from bytes import ByteArray
from std import print
from unittest import assert_str_equals

fn main() -> int:
    test_pack()
    print("OK")
    return 0

fn test_pack():
    let b = ByteArray()
    b.pack16_be(0x4302)
    b.append(5)
    b.pack32_le(0x1337)
    assert_str_equals(b.as_hex(), "43020537130000")

