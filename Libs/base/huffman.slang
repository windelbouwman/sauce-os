"""
Procedures related to Huffman coding.
"""

from utils import panic
from hashmap import HashMap, new_hashmap_int
from bytes import ByteReader, ByteArray, Bytes

pub fn decode_symbol(tree: Tree, bit_reader: BitReader) -> int:
	""" Decode a value with the given Huffman tree """
	var len = 1
	var code = 0
	var index = 0
	var first = 0
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

pub fn create_table(tree: Tree) -> HashMap[int,CodeEntry]:
	let table: HashMap[int,CodeEntry] = new_hashmap_int()
	var first = 0
	var index = 0
	var len = 1
	while len <= 16:
		let count = tree.counts[len]
		var i = 0
		while i < count:
			let symbol = tree.symbols[index + i]
			let code = first + i
			let entry = CodeEntry(code, length: len)
			table.insert(key: symbol, value: entry)
			i += 1
		first = (first + count) << 1
		index += count
		len += 1
	table

pub struct CodeEntry:
	code: int
	length: int

pub fn encode_symbol(table: HashMap[int,CodeEntry], symbol: int, bit_writer: BitWriter):
	let entry = table.get(key: symbol)
	# print("Write symbol={symbol}, code={entry.code}, len={entry.length}")
	# Huffman codes are written with the MSB transmitted first:
	if entry.length == 0:
		panic("Invalid length for symbol: {symbol}")
	var bit = entry.length
	while bit > 0:
		bit -= 1
		let value = (entry.code >> bit) & 1
		bit_writer.write_bits(n: 1, value)

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
			var value = m_bitbuf
			while m_bitcnt < n:
				let byte = m_reader.read_byte()
				value = (byte << m_bitcnt) | value
				m_bitcnt += 8
			m_bitbuf = value >> n
			m_bitcnt -= n
			let mask = (1 << n) - 1
			value & mask

pub class BitWriter:
	pub var m_output: ByteArray
	var m_bitbuf: int = 0
	var m_bitcnt: int = 0

	pub fn write_bits(n: int, value: int):
		# DEFLATE endianness
		m_bitbuf = (value << m_bitcnt) | m_bitbuf
		m_bitcnt += n

		# Flush full bytes to output:
		while m_bitcnt >= 8:
			m_output.append(m_bitbuf & 0xFF)
			m_bitbuf = m_bitbuf >> 8
			m_bitcnt -= 8

	pub fn flush():
		if m_bitcnt > 0:
			m_output.append(m_bitbuf & 0xFF)
			m_bitcnt = 0
			m_bitbuf = 0

	pub fn to_bytes() -> Bytes:
		flush()
		m_output.to_bytes()

pub struct Tree:
	counts: [int]
	symbols: [int]

pub fn zero_int_array(size: int) -> [int]:
	var array = [size : int]
	var i = 0
	while i < size:
		array[i] = 0
		i += 1
	array
