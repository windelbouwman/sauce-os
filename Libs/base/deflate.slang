
# Implement RFC 1951: "deflate" format.
# DEFLATE uses huffman trees and LZ77 compression.

from utils import panic, unimplemented, assert
from utils import log_trace, log_debug
from bytes import Bytes, ByteArray, ByteReader
from vectype import Vector, new_vector, new_vector_of_size

pub fn deflate_decompress(data?: Bytes) -> Bytes:
	# Decompress the given data using deflate
	# See: RFC 1951
	let reader = data.into_reader()
	deflate_decompress_from_reader(reader)

fn deflate_decompress_from_reader(reader: ByteReader) -> Bytes:
	let decoder = new_deflate_decoder(reader)
	decoder.deflate()

pub fn new_deflate_decoder(reader: ByteReader) -> DeflateDecoder:
	let bit_reader = BitReader(m_reader: reader)
	DeflateDecoder(m_bit_reader: bit_reader)

pub fn deflate_compress(data: Bytes) -> Bytes:
	# Implementation 1: copy uncompressed:
	let out = ByteArray()
	let index = 0
	while index < data.len():
		let size = data.len() - index
		let last_block = false
		if size > 4000:
			size = 4000
		else:
			last_block = true
		
		log_trace("Size: {size}")

		if last_block:
			out.append(1)
		else:
			out.append(0)

		out.pack_u16_le(size)
		out.pack_u16_le(0xFFFF ^ size)

		let i = 0
		while i < size:
			out.append(data.get(index))
			index += 1
			i += 1

	out.to_bytes()

pub class DeflateDecoder:
	var m_bit_reader: BitReader
	var m_output: ByteArray = ByteArray()

	pub fn deflate() -> Bytes:
		# Main deflate loop.
		loop:
			# Read block header:
			let bfinal = read_bits(1)  # last block or not
			let btype = read_bits(2)  # Block type
			log_debug("bfinal={bfinal} btype={btype}")

			if btype == 0:  # no compression
				copy_uncompressed()
			elif btype == 1:  # Fixed huffman table
				let pair = create_fixed_trees()
				inflate_block(pair)
			elif btype == 2:  # dynamic huffman table
				let pair = read_dynamic_tree()
				inflate_block(pair)
			elif btype == 3:  # Reserved type
				panic("Reserved btype")
			else:
				panic("invalid btype: {btype}")

			if bfinal == 1:
				break
		m_output.to_bytes()

	fn copy_uncompressed():
		let len = read_u16_le()
		let nlen = read_u16_le()  # Inverted version
		log_debug("copy_uncompressed len={len} nlen={nlen}")
		# TODO: what to do with nlen? Check it?
		while len > 0:
			emit_byte(read_byte())
			len -= 1

	fn read_dynamic_tree() -> TreePair:
		# Read dynamic huffman trees
		let hlit = read_bits(5) + 257  # Number of literal/length codes
		let hdist = read_bits(5) + 1  # Number of distance codes
		let hclen = read_bits(4) + 4  # Number of length codes

		log_debug("hlit={hlit}, hdist={hdist}, hclen={hclen}")

		let lengths: Vector[int] = new_vector_of_size(size: 19, default: 0)
		let i = 0
		let clcidx = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
		while i < hclen:
			let clen = read_bits(3)
			let index = clcidx[i]
			lengths.set(index, value: clen)
			i += 1
		let tree = create_tree(lengths)

		# Read a fair amount of code lengths:
		lengths = new_vector()
		while lengths.len() < hlit + hdist:
			let symbol = decode_symbol(tree)
			# print("symbol={symbol}")
			let times = 0
			let L = 0
			if symbol < 16:
				L = symbol
				times = 1
			elif symbol == 16:  # Copy previous value 3 to 6 times
				L = lengths.last()
				times = read_bits(2) + 3
			elif symbol == 17:  # Repeat 0 value 3 to 10 times
				L = 0
				times = read_bits(3) + 3
			elif symbol == 18:  # Repeat 0 value 11 - 138 times
				L = 0
				times = read_bits(7) + 11
			else:
				panic("Invalid value")

			# print("times={times} L={L}")
			while times > 0:
				times -= 1
				lengths.append(L)
		# print("lengths.len={lengths.len()}")

		assert(condition: lengths.len() == hlit + hdist, message: "lengths must be hlit + hdist")
		# Split vector
		let first = create_tree(lengths: lengths.take(hlit))
		let second = create_tree(lengths: lengths.skip(hlit))
		TreePair(first, second)

	fn inflate_block(pair: TreePair):
		# Decompress huffman coded data.
		# By using either custom or fixed huffman tree.

		# 29 extra length bits:
		let length_bits = [0, 0, 0, 0, 0, 0, 0, 0,  1,  1,  1,  1,  2,  2,  2,  2,  3,  3,  3,  3,  4,  4,  4,  4,   5,   5,   5,   5,   0]
		let length_base = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
		# 30 extra distance bits:
		let dist_bits = [0, 0, 0, 0, 1, 1, 2, 2,  3,  3,  4,  4,  5,  5,  6,   6,   7,   7,   8,   8,   9,    9,    10,   10,   11,   11,   12,   12,    13,    13]
		let dist_base = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
		loop:
			let symbol = decode_symbol(tree: pair.first)
			# print("Symbol: {symbol}")
			if symbol < 256:  # Literal byte
				emit_byte(symbol)
			elif symbol == 256:  # End-of-block
				break
			else:  # Length / distance combination
				assert(condition: symbol > 256, message: "value must be larger than 256 here: {symbol}")
				symbol -= 257

				assert(condition: symbol < 29, message: "Invalid length code: {symbol}")
				let length = read_bits(length_bits[symbol]) + length_base[symbol]

				symbol = decode_symbol(tree: pair.second)
				assert(condition: symbol < 30, message: "Invalid distance code: {symbol}")
				let distance = read_bits(dist_bits[symbol]) + dist_base[symbol]

				log_trace("length={length} distance={distance}")
				let index = m_output.len() - distance
				while length > 0:
					let value = m_output.get(index)
					emit_byte(value)
					index += 1
					length -= 1

	fn decode_symbol(tree: Tree) -> int:
		# Decode a value with the given Huffman tree
		let len = 1
		let code = 0
		let index = 0
		let first = 0
		while len <= 16:
			code = code | read_bits(1)
			let count = tree.counts[len]
			if code - count < first:
				return tree.symbols[index + (code - first)]

			index += count
			first = (first + count) << 1
			code = code << 1

			len += 1

		unimplemented("Decode symbol")

	fn read_bits(n?: int) -> int:
		m_bit_reader.read_bits(n)

	fn read_byte() -> int:
		m_bit_reader.m_reader.read_byte()

	fn read_u16_le() -> int:
		m_bit_reader.m_bitbuf = 0
		m_bit_reader.m_bitcnt = 0
		m_bit_reader.m_reader.read_u16_le()

	fn emit_byte(b?: int):
		assert(condition: b < 256, message: "Byte values must be smaller than 256")
		m_output.append(b)


class BitReader:
	pub var m_bitbuf: int = 0
	pub var m_bitcnt: int = 0
	pub var m_reader: ByteReader

	pub fn read_bits(n?: int) -> int:
		let value = m_bitbuf
		while m_bitcnt < n:
			let byte = m_reader.read_byte()
			value = (byte << m_bitcnt) | value
			m_bitcnt += 8
		m_bitbuf = value >> n
		m_bitcnt -= n
		let mask = (1 << n) - 1
		value & mask

struct Tree:
	counts: [int]
	symbols: [int]

struct TreePair:
	first: Tree
	second: Tree

fn zero_int_array(size: int) -> [int]:
	let array = [size : int]
	let i = 0
	while i < size:
		array[i] = 0
		i += 1
	array

fn create_tree(lengths: Vector[int]) -> Tree:
	# Given a set of lengths, calculate the Huffman tree.
	# A Huffman tree can be defined entirely by the bit lengths
	# of each symbol.

	# Step 1: count number of codes for each non-zero length
	let counts: [int] = zero_int_array(size: 17)

	for length in lengths:
		assert(condition: length < 17, message: "Length must be less than 17")
		counts[length] = counts[length] + 1

	# Step 2: determine start code for each bit length:
	let offsets: [int] = zero_int_array(size: 17)

	let bits = 1
	while bits < 16:
		offsets[bits + 1] = offsets[bits] + counts[bits]
		bits += 1

	# Step 3: Fill in table with used symbols:
	let symbols: [int] = zero_int_array(size: 288)

	let symbol = 0
	for length in lengths:
		if length > 0:
			symbols[offsets[length]] = symbol
			offsets[length] = offsets[length] + 1
		symbol += 1

	Tree:
		counts
		symbols

fn create_fixed_trees() -> TreePair:
	let first = create_fixed_literal_length_tree()
	let second = create_fixed_distance_tree()
	TreePair(first, second)

fn create_fixed_literal_length_tree() -> Tree:
	let lengths: Vector[int] = new_vector()
	let symbol = 0
	while symbol < 144:
		lengths.append(8)
		symbol += 1
	while symbol < 256:
		lengths.append(9)
		symbol += 1
	while symbol < 280:
		lengths.append(7)
		symbol += 1
	while symbol < 288:
		lengths.append(8)
		symbol += 1
	create_tree(lengths)

fn create_fixed_distance_tree() -> Tree:
	let lengths: Vector[int] = new_vector()
	let symbol = 0
	while symbol < 30:
		lengths.append(5)
		symbol += 1
	create_tree(lengths)
