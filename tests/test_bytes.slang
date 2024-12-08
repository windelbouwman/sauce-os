
from bytes import ByteArray, bytes_from_hex_text
from std import print
from unittest import assert_str_equals

pub fn main() -> int:
    test_hex_text_conversion()
    test_pack()
    test_concatenation()
    print("OK")
    0

fn test_hex_text_conversion():
    let hex_text = "112233BCF2"
    let data = bytes_from_hex_text(text: hex_text)
    assert_str_equals(hex_text, data.as_hex())

fn test_pack():
    let b = ByteArray()
    b.pack_u16_be(0x4302)
    b.append(5)
    b.pack_u32_le(0x1337)
    assert_str_equals(b.as_hex(), "43020537130000")

fn test_concatenation():
    let data1 = bytes_from_hex_text(text: "ABCD")
    let data2 = bytes_from_hex_text(text: "1234EF")
    let data3 = data1.concat(other: data2)
    assert_str_equals(data3.as_hex(), "ABCD1234EF")
