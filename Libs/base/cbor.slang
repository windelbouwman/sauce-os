module base.cbor
"""CBOR (Concise Binary Object Representation)

See also: https://cbor.io/
"""
from std import str_len
from utils import unimplemented
from bytes import Bytes, ByteArray, bytes_from_ascii

pub class CborWriter:
	var m_buffer: ByteArray = ByteArray()

	pub fn write_int(value?: int):
		if value < 0:
			emit_varsized(major: 1, info: -1 - value)
		else:
			emit_varsized(major: 0, info: value)

	pub fn write_bool(value?: bool):
		write_header(major: 7, info: 21 if value else 20)

	pub fn write_null():
		write_header(major: 7, info: 22)

	pub fn write_undefined():
		write_header(major: 7, info: 23)

	pub fn write_bytes(data?: Bytes):
		emit_varsized(major: 2, info: data.len())
		emit_bytes(data)

	pub fn write_string(text?: str):
		let n = str_len(text)
		emit_varsized(major: 3, info: n)
		emit_bytes(bytes_from_ascii(text))

	pub fn start_array(size: int):
		emit_varsized(major: 4, info: size)

	pub fn start_map(size: int):
		emit_varsized(major: 5, info: size)

	pub fn write_float(value?: float):
		write_header(major: 7, info: 27)
		m_buffer.pack_f64_be(value)

	pub fn finish() -> Bytes:
		m_buffer.to_bytes()

	fn emit_varsized(major: int, info: int):
		if info < 24:
			write_header(major, info)
		elif info < 256:
			write_header(major, info: 24)
			emit_u8(info)
		elif info < 65536:
			write_header(major, info: 25)
			emit_u16(info)
		elif info < 0x80000000:
			write_header(major, info: 26)
			emit_u32(info)
		else:
			unimplemented("Large integers")

	fn write_header(major: int, info: int):
		emit_byte((major << 5) | info)

	fn emit_u32(value?: int):
		emit_byte((value >> 24) & 0xFF)
		emit_byte((value >> 16) & 0xFF)
		emit_byte((value >> 8) & 0xFF)
		emit_byte(value & 0xFF)

	fn emit_u16(value?: int):
		emit_byte((value >> 8) & 0xFF)
		emit_byte(value & 0xFF)

	fn emit_u8(value?: int):
		emit_byte(value)

	fn emit_bytes(data?: Bytes):
		m_buffer.extend(data)

	fn emit_byte(value?: int):
		m_buffer.append(value)

class CborReader:
	var m_a: int = 0

	fn a():
		pass
