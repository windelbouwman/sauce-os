module base.leb128
"""LEB128 encoding."""

from utils import panic
from bytes import ByteArray, ByteReader

pub fn pack_unsigned_leb128(out: ByteArray, value: int):
	if value < 0:
		panic("pack_unsigned_leb128 requires non-negative value")
	loop:
		let byte = value & 0x7F
		value = value >> 7
		if value == 0:
			out.append(byte)
			break
		else:
			out.append(byte | 0x80)

pub fn pack_signed_leb128(out: ByteArray, value: int):
	loop:
		let byte = value & 0x7F
		value = value >> 7
		let sign_bit: bool = (byte & 0x40) == 0x40
		if (value == 0 and not sign_bit) or (value == -1 and sign_bit):
			out.append(byte)
			break
		else:
			out.append(byte | 0x80)

pub fn unpack_unsigned_leb128(reader: ByteReader) -> int:
	var value = 0
	var shift = 0
	loop:
		let b = reader.read_byte()
		value = ((b & 0x7F) << shift) | value
		if b & 0x80 == 0:
			break
		shift += 7
	value

pub fn unpack_signed_leb128(reader: ByteReader) -> int:
	var value = 0
	var shift = 0
	loop:
		let b = reader.read_byte()
		value = ((b & 0x7F) << shift) | value
		shift += 7
		if b & 0x80 == 0:
			if b & 0x40 != 0:
				let mask = (1 << shift) - 1
				value = -(value ^ mask) - 1
			break
	value
