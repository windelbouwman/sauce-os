module main
"""Test LEB128 encoding"""

from base import leb128
from base.unittest import assert_bytes_equals, assert_int_equals
from std import print
from base.bytes import ByteArray, bytes_from_hex_text, ByteReader

pub fn main() -> int:
	test_unsigned_leb128(value: 0, expected: "00")
	test_unsigned_leb128(value: 42, expected: "2A")
	test_unsigned_leb128(value: 127, expected: "7F")
	test_unsigned_leb128(value: 128, expected: "8001")
	test_unsigned_leb128(value: 255, expected: "FF01")
	test_unsigned_leb128(value: 0xFFFF, expected: "FFFF03")
	test_unsigned_leb128(value: 624485, expected: "e58e26")

	test_signed_leb128(value: -64, expected: "40")
	test_signed_leb128(value: 2, expected: "02")
	test_signed_leb128(value: -2, expected: "7E")
	test_signed_leb128(value: 127, expected: "FF00")
	test_signed_leb128(value: -127, expected: "817F")
	test_signed_leb128(value: 128, expected: "8001")
	test_signed_leb128(value: -128, expected: "807F")
	test_signed_leb128(value: 129, expected: "8101")
	test_signed_leb128(value: -129, expected: "FF7E")
	test_signed_leb128(value: -624485, expected: "9bf159")

	print("OK")
	0

fn test_unsigned_leb128(value: int, expected: str):
	let out = ByteArray()
	leb128.pack_unsigned_leb128(out, value)
	let data = out.to_bytes()
	assert_bytes_equals(data, expected: bytes_from_hex_text(text: expected))
	let reader = ByteReader(m_bytes: data)
	let value2 = leb128.unpack_unsigned_leb128(reader)
	assert_int_equals(value, value2)

fn test_signed_leb128(value: int, expected: str):
	let out = ByteArray()
	leb128.pack_signed_leb128(out, value)
	let data = out.to_bytes()
	assert_bytes_equals(data, expected: bytes_from_hex_text(text: expected))
	let reader = ByteReader(m_bytes: data)
	let value2 = leb128.unpack_signed_leb128(reader)
	assert_int_equals(value, value2)
