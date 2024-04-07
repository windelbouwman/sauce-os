
from bytes import ByteArray, bytes_from_hex_text
from std import print
from unittest import assert_str_equals

fn main() -> int:
    test_hex_text_conversion()
    test_pack()
    print("OK")
    return 0

fn test_hex_text_conversion():
    let hex_text = "112233BCF2"
    let data = bytes_from_hex_text(text: hex_text)
    assert_str_equals(hex_text, data.as_hex())

fn test_pack():
    let b = ByteArray()
    b.pack16_be(0x4302)
    b.append(5)
    b.pack32_le(0x1337)
    assert_str_equals(b.as_hex(), "43020537130000")
