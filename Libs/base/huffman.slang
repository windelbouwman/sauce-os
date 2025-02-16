"""
Procedures related to Huffman coding.
"""

from utils import panic
from bytes import ByteReader

pub fn decode_symbol(tree: Tree, bit_reader: BitReader) -> int:
	""" Decode a value with the given Huffman tree """
	let len = 1
	let code = 0
	let index = 0
	let first = 0
	while len <= 16:
		code = code | bit_reader.read_bits(n: 1)
		let count = tree.counts[len]
		if code - count < first:
			return tree.symbols[index + (code - first)]

		index += count
		first = (first + count) << 1
		code = code << 1

		len += 1

	panic("Decode symbol failed")

pub class BitReader:
	pub var m_bitbuf: int = 0
	pub var m_bitcnt: int = 0
	pub var m_reader: ByteReader
	pub var m_reverse: bool

	pub fn read_bits(n?: int) -> int:
		# TODO: implement different classes of bitreaders with a common interface.
		if n == 0:
			return 0
		if m_reverse:
			# MSB first?
			# Used for JPEG
			while m_bitcnt < n:
				let byte = m_reader.read_byte()
				m_bitbuf = (m_bitbuf << 8) | byte
				m_bitcnt += 8
			m_bitcnt -= n
			let mask = (1 << n) - 1
			(m_bitbuf >> m_bitcnt) & mask
		else:
			# used for deflate
			let value = m_bitbuf
			while m_bitcnt < n:
				let byte = m_reader.read_byte()
				value = (byte << m_bitcnt) | value
				m_bitcnt += 8
			m_bitbuf = value >> n
			m_bitcnt -= n
			let mask = (1 << n) - 1
			value & mask

pub struct Tree:
	counts: [int]
	symbols: [int]

pub fn zero_int_array(size: int) -> [int]:
	let array = [size : int]
	let i = 0
	while i < size:
		array[i] = 0
		i += 1
	array
