
# Data types for bytes

from std import ord, chr, pack_f64
from utils import assert, panic
from vectype import Vector, new_vector
from strlib import hex_char, hex_digit_to_int, is_hex_digit, is_space

pub class Bytes:
	""" Immutable bytes """
	var m_bytes: [uint8]
	var m_size: int

	pub fn len() -> int:
		m_size

	pub fn get(index: int) -> int:
		int(m_bytes[index])

	pub fn get_byte(index: int) -> uint8:
		m_bytes[index]

	pub fn set_byte(index: int, value: uint8):
		m_bytes[index] = value

	pub fn concat(other: Bytes) -> Bytes:
		# Concatenate two byte sequences
		concat2(a: this, b: other)

	pub fn as_hex() -> str:
		# Return bytes as hexadecimal text
		var txt = ""
		var index = 0
		while index < m_size:
			let b = m_bytes[index]
			txt = txt + byte_as_hex(b)
			index += 1
		txt

	pub fn as_array() -> [uint8]:
		m_bytes

	pub fn into_reader() -> ByteReader:
		ByteReader(m_bytes: this)

	pub fn as_ascii() -> str:
		return bytes_to_ascii(data: this)

fn concat2(a: Bytes, b: Bytes) -> Bytes:
	let out = new_bytes_with_size(size: a.len() + b.len())
	var index = 0
	var index1 = 0
	while index1 < a.len():
		out.set_byte(index, value: a.get_byte(index: index1))
		index += 1
		index1 += 1
	var index2 = 0
	while index2 < b.len():
		out.set_byte(index, value: b.get_byte(index: index2))
		index += 1
		index2 += 1
	out

pub class ByteReader:
	# read byte at a time
	var m_bytes: Bytes
	var m_index: int = 0

	pub fn at_end() -> bool:
		m_index >= m_bytes.len()

	pub fn read_bytes(size: int) -> Bytes:
		var i = 0
		let ba = ByteArray()
		while i < size:
			ba.append(read_byte())
			i += 1
		ba.to_bytes()

	pub fn peek_byte(ahead: int) -> int:
		if m_index + ahead < m_bytes.len():
			return m_bytes[m_index + ahead]
		else:
			panic("Cannot peek past end of bytes")

	pub fn read_byte() -> int:
		if m_index < m_bytes.len():
			let value = m_bytes[m_index]
			m_index += 1
			value
		else:
			panic("Cannot read past end of bytes")

	pub fn read_u16_be() -> int:
		let b1 = read_byte()
		let b2 = read_byte()
		(b1 << 8) | b2

	pub fn read_u16_le() -> int:
		let b1 = read_byte()
		let b2 = read_byte()
		(b2 << 8) | b1

	pub fn read_u32_be() -> int:
		let b1 = read_byte()
		let b2 = read_byte()
		let b3 = read_byte()
		let b4 = read_byte()
		(b1 << 24) | (b2 << 16) | (b3 << 8) | b4

	pub fn read_u32_le() -> int:
		let b1 = read_byte()
		let b2 = read_byte()
		let b3 = read_byte()
		let b4 = read_byte()
		(b4 << 24) | (b3 << 16) | (b2 << 8) | b1

pub class ByteArray:
	# Mutable bytes
	var m_bytes: Vector[uint8] = new_vector()

	pub fn append(byte?: int):
		m_bytes.append(uint8(byte))

	pub fn get(index: int) -> int:
		int(m_bytes[index])

	pub fn set(index: int, value: int):
		m_bytes.set(index, value: uint8(value))

	pub fn extend(bytes?: Bytes):
		for b in bytes:
			append(b)

	pub fn pack_f64_le(value: float):
		let buffer: [uint8] = [8 : uint8]
		pack_f64(value, buffer)
		var index = 0
		while index < 8:
			append(int(buffer[index]))
			index += 1

	pub fn pack_u64_le(value?: int):
		append(value & 0xFF)
		append((value >> 8) & 0xFF)
		append((value >> 16) & 0xFF)
		append((value >> 24) & 0xFF)
		append((value >> 32) & 0xFF)
		append((value >> 40) & 0xFF)
		append((value >> 48) & 0xFF)
		append((value >> 56) & 0xFF)

	pub fn pack_u64_be(value?: int):
		append((value >> 56) & 0xFF)
		append((value >> 48) & 0xFF)
		append((value >> 40) & 0xFF)
		append((value >> 32) & 0xFF)
		append((value >> 24) & 0xFF)
		append((value >> 16) & 0xFF)
		append((value >> 8) & 0xFF)
		append(value & 0xFF)

	pub fn pack_u32_le(value?: int):
		append(value & 0xFF)
		append((value >> 8) & 0xFF)
		append((value >> 16) & 0xFF)
		append((value >> 24) & 0xFF)

	pub fn pack_u32_be(value?: int):
		append((value >> 24) & 0xFF)
		append((value >> 16) & 0xFF)
		append((value >> 8) & 0xFF)
		append(value & 0xFF)

	pub fn pack_u16_le(value?: int):
		append(value & 0xff)
		append((value >> 8) & 0xFF)

	pub fn pack_u16_be(value?: int):
		append((value & 0xff00) >> 8)
		append(value & 0xff)

	pub fn is_empty() -> bool:
		m_bytes.is_empty()

	pub fn len() -> int:
		m_bytes.len()

	pub fn to_bytes() -> Bytes:
		let out = new_bytes_with_size(size: m_bytes.len())
		var index = 0
		while index < m_bytes.len():
			out.set_byte(index, value: m_bytes[index])
			index += 1
		out

	pub fn as_hex() -> str:
		to_bytes().as_hex()

fn byte_as_hex(byte?: uint8) -> str:
	let c1 = hex_char(int(byte) & 0xF)
	let c2 = hex_char((int(byte) & 0xF0) >> 4)
	"{c2}{c1}"

pub fn bytes_from_hex_text(text: str) -> Bytes:
	let output = ByteArray()
	var value = 0
	var n_bits = 0
	for c in text:
		if is_hex_digit(c):
			value = (value << 4) | hex_digit_to_int(c)
			n_bits += 4
			if n_bits == 8:
				output.append(value)
				value = 0
				n_bits = 0
		elif is_space(c):
			pass
		else:
			panic("Invalid hex char '{c}'")
	assert(condition: n_bits == 0, message: "Hexadecimal text must contain whole bytes")
	output.to_bytes()

pub fn new_bytes() -> Bytes:
	let output = ByteArray()
	output.to_bytes()

fn new_bytes_with_size(size: int) -> Bytes:
	"""Bytes object with the given size. Uninitialized memory."""
	let m_bytes = [size : uint8]
	Bytes(m_bytes, m_size: size)

pub fn fill_bytes(n: int, fill: int) -> Bytes:
	let output = new_bytes_with_size(size: n)
	var index = 0
	while index < n:
		output.set_byte(index, value: uint8(fill))
		index += 1
	output

pub fn bytes_from_ascii(text: str) -> Bytes:
	let output = ByteArray()
	for c in text:
		output.append(ord(c))
	output.to_bytes()

pub fn bytes_to_ascii(data: Bytes) -> str:
	# Interpret bytes as ascii data
	var result = ""
	for b in data:
		result = result + "{chr(b)}"
	result
