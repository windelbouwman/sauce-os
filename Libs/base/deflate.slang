"""
Implement RFC 1951: deflate format.

DEFLATE uses huffman trees and LZ77 compression.
"""

from utils import panic, assert, unimplemented
from logging import log_trace, log_debug
from listtype import List, list1
from bytes import Bytes, ByteArray, ByteReader
from vectype import Vector, new_vector, new_vector_of_size
from huffman import Tree, BitReader, decode_symbol, zero_int_array
from heapq import new_priority_queue_with_capacity, PriorityQueue
from huffman import BitWriter, create_table, encode_symbol, CodeEntry
from hashmap import HashMap, new_hashmap_int

pub fn deflate_decompress(data?: Bytes) -> Bytes:
	""" Decompress the given data using deflate
	See: RFC 1951
	"""
	let reader = data.into_reader()
	deflate_decompress_from_reader(reader)

fn deflate_decompress_from_reader(reader: ByteReader) -> Bytes:
	let decoder = new_deflate_decoder(reader)
	decoder.deflate()

pub fn new_deflate_decoder(reader: ByteReader) -> DeflateDecoder:
	let bit_reader = BitReader(m_reader: reader, m_reverse: false)
	DeflateDecoder(m_bit_reader: bit_reader)

pub fn deflate_compress(data: Bytes) -> Bytes:
	""" Compress data in DEFLATE format """
	let encoder = DeflateCompressor(m_data: data)
	encoder.compress()

enum Action:
	Literal(value: int)
	Copy(distance: int, length: int)

fn find_index(base: [int], bits: [int], size: int, value: int) -> int:
	# TODO: we could use some bisecting here?
	var i = 0
	while i < size:
		if (value >= base[i]) and (value < base[i] + (1 << bits[i])):
			return i
		else:
			i += 1
	unimplemented("Value not found: {value}")

struct TreeNode:
	freq: int
	kind: TreeNodeKind

enum TreeNodeKind:
	Leaf(symbol: int)
	Internal(left: TreeNode, right: TreeNode)

fn cmp_TreeNode(a: TreeNode, b: TreeNode) -> bool:
	a.freq < b.freq

fn get_widths(frequencies: [int], size: int) -> Vector[int]:
	""" Given a set of frequencies, determine the width in bits of each symbol. """
	# Create priority queue:
	let q: PriorityQueue[TreeNode] = new_priority_queue_with_capacity(capacity: size, f: cmp_TreeNode)
	var i = 0
	while i < size:
		let freq = frequencies[i]
		if freq > 0:
			q.push(TreeNode(freq, kind: TreeNodeKind.Leaf(symbol: i)))
		i += 1

	# Construct the tree:
	while q.len() > 1:
		let left = q.pop()
		let right = q.pop()
		q.push(TreeNode(freq: left.freq + right.freq, kind: TreeNodeKind.Internal(left, right)))

	let root_node = q.pop()

	# Assign widths:
	let widths: Vector[int] = new_vector_of_size(size, default: 0)
	assign_bit_width(widths, node: root_node, level: 0)
	widths

fn assign_bit_width(widths: Vector[int], node: TreeNode, level: int):
	case node.kind:
		Leaf(symbol):
			widths.set(index: symbol, value: level)
		Internal(left, right):
			assign_bit_width(widths, node: left, level: level + 1)
			assign_bit_width(widths, node: right, level: level + 1)

enum RunLengthOpcode:
	Literal(value: int) # 0 .. 15
	Repeat(n: int) # 16 -> repeat previous symbol
	FewZeroes(n: int) # 17 -> repeat zeroes
	ManyZeroes(n: int) # 18 -> repeat zeroes

class RunLengthEncoder:
	var m_opcodes: List[RunLengthOpcode] = List()

	pub fn encode(values: Vector[int]) -> List[RunLengthOpcode]:
		""" Run length encoding """
		var count = 1
		var value = values.get(index: 0)

		var i = 1
		while i < values.len():
			let new_value = values.get(index: i)
			if value == new_value:
				count += 1
			else:
				emit_run(value, count)
				value = new_value
				count = 1
			i += 1
		emit_run(value, count)
		m_opcodes

	fn emit_run(value: int, count: int):
		if count == 0:
			return

		if value == 0:  # Repeat zero so many times
			while count > 0:
				var rep = count
				if rep >= 11:
					if rep > 138:
						rep = 138
					emit(RunLengthOpcode.ManyZeroes(rep))
					count -= rep
				elif rep >= 3:  # Repeat 3-10 zeroes
					emit(RunLengthOpcode.FewZeroes(rep))
					count -= rep
				else:
					emit(RunLengthOpcode.Literal(0))
					count -= 1
		else:  # Non-zero value!
			emit(RunLengthOpcode.Literal(value))
			count -= 1
			while count > 0:
				var rep = count
				if rep >= 3:
					if rep > 6:
						rep = 6
					emit(RunLengthOpcode.Repeat(rep))
					count -= rep
				else:
					emit(RunLengthOpcode.Literal(value))
					count -= 1

	fn emit(opcode?: RunLengthOpcode):
		m_opcodes.append(opcode)

class DeflateCompressor:
	var m_data: Bytes
	var m_index: int = 0
	var m_level: int = 2
	var m_bit_writer: BitWriter = BitWriter(m_output: ByteArray())
	var m_hash_table: HashMap[int,List[int]] = new_hashmap_int()

	pub fn compress() -> Bytes:
		if m_level == 0:
			no_compression()
		else:
			some_compression()
		m_bit_writer.flush()
		m_bit_writer.m_output.to_bytes()

	fn write_block_header(last_block: int, btype: int):
		log_trace("last={last_block}, btype={btype}")
		write_bits(n: 1, value: last_block)  # Last block (1 bit field)
		write_bits(n: 2, value: btype)  # Block type (2 bits field)

	fn some_compression():
		while m_index < m_data.len():
			let actions = create_actions()
			let pair = determine_trees(actions)
			write_actions(pair, actions)

	fn determine_trees(actions: List[Action]) -> TreePair:
		log_trace("determine tree")

		let length_bits = [0, 0, 0, 0, 0, 0, 0, 0,  1,  1,  1,  1,  2,  2,  2,  2,  3,  3,  3,  3,  4,  4,  4,  4,   5,   5,   5,   5,   0]
		let length_base = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]

		# 30 extra distance bits:
		let dist_bits = [0, 0, 0, 0, 1, 1, 2, 2,  3,  3,  4,  4,  5,  5,  6,   6,   7,   7,   8,   8,   9,    9,    10,   10,   11,   11,   12,   12,    13,    13]
		let dist_base = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]

		var freqencies_1 = zero_int_array(size: 288) # 0 .. 287
		var freqencies_2 = zero_int_array(size: 32)  # 0 .. 31
		freqencies_2[0] = 1
		freqencies_2[1] = 1

		# Determine symbol frequencies:
		for action in actions:
			case action:
				Literal(symbol):
					freqencies_1[symbol] = freqencies_1[symbol] + 1
				Copy(distance, length):
					var i = find_index(base: length_base, bits: length_bits, size: 29, value: length)
					let symbol = 257 + i
					freqencies_1[symbol] = freqencies_1[symbol] + 1

					i = find_index(base: dist_base, bits: dist_bits, size: 30, value: distance)
					freqencies_2[i] = freqencies_2[i] + 1

		freqencies_1[256] = freqencies_1[256] + 1

		# Now assign bit patterns given the frequencies
		let lengths1 = get_widths(frequencies: freqencies_1, size: 285)
		let lengths2 = get_widths(frequencies: freqencies_2, size: 30)

		let fixed_lengths1 = create_fixed_literal_lengths()
		let fixed_lengths2 = create_fixed_distance_lengths()

		# Now we can calculate the entire bit size, using frequencies and bit lengths!
		var dynamic_bit_size = 0
		var static_bit_size = 0
		var i = 0
		while i < lengths1.len():
			dynamic_bit_size += freqencies_1[i] * lengths1.get(index: i)
			static_bit_size += freqencies_1[i] * fixed_lengths1.get(index: i)
			i += 1

		i = 0
		while i < lengths2.len():
			dynamic_bit_size += freqencies_2[i] * lengths2.get(index: i)
			static_bit_size += freqencies_2[i] * fixed_lengths2.get(index: i)
			i += 1

		# Concatenate length vectors:

		# TODO: strip-off zero lengths
		let all_lengths: Vector[int] = new_vector()
		all_lengths.extend(lengths1)
		all_lengths.extend(lengths2)

		# Run length encode the code lengths
		let rle = RunLengthEncoder()
		let opcodes = rle.encode(values: all_lengths)

		# Determine frequencies:
		var code_freqencies = zero_int_array(size: 19)  # 0 .. 18
		for opcode in opcodes:
			case opcode:
				Literal(value):
					code_freqencies[value] = code_freqencies[value] + 1
				Repeat(rep):
					code_freqencies[16] = code_freqencies[16] + 1
					dynamic_bit_size += 2
				FewZeroes(rep):
					code_freqencies[17] = code_freqencies[17] + 1
					dynamic_bit_size += 3
				ManyZeroes(rep):
					code_freqencies[18] = code_freqencies[18] + 1
					dynamic_bit_size += 7

		let code_lengths = get_widths(frequencies: code_freqencies, size: 19)
		i = 0
		while i < code_lengths.len():
			dynamic_bit_size += code_freqencies[i] * code_lengths.get(index: i)
			i += 1

		dynamic_bit_size += 5 + 5 + 4 # Header of dynamic trees
		dynamic_bit_size += 19 * 3  # tree encoding bit sizes, 3 bits per bit size

		log_trace("dynamic_bit_size={dynamic_bit_size}, static_bit_size={static_bit_size}")

		let last_block = if m_index == m_data.len():
			1
		else:
			0
		if dynamic_bit_size < static_bit_size:
			write_block_header(last_block, btype: 2)
			write_dynamic_table(lengths1, lengths2, code_lengths, opcodes)
			let first = create_tree(lengths: lengths1)
			let second = create_tree(lengths: lengths2)
			TreePair(first, second)
		else:
			write_block_header(last_block, btype: 1)
			let first = create_tree(lengths: fixed_lengths1)
			let second = create_tree(lengths: fixed_lengths2)
			TreePair(first, second)

	fn write_dynamic_table(lengths1: Vector[int], lengths2: Vector[int], code_lengths: Vector[int], opcodes: List[RunLengthOpcode]):
		let hlit = lengths1.len() - 257
		let hdist = lengths2.len() - 1
		let hclen = code_lengths.len()
		log_trace("hlit={hlit} hdist={hdist} hclen={hclen}")
		write_bits(n: 5, value: hlit)
		write_bits(n: 5, value: hdist)
		write_bits(n: 4, value: hclen - 4)

		var i = 0
		let clcidx = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
		while i < hclen:
			let clen = code_lengths.get(index: clcidx[i])
			write_bits(n: 3, value: clen)
			i += 1
		let x_table = create_table(tree: create_tree(lengths: code_lengths))
		run_length_encode(table: x_table, opcodes)

	fn run_length_encode(table: HashMap[int,CodeEntry], opcodes: List[RunLengthOpcode]):
		""" Run length encoding """
		for opcode in opcodes:
			case opcode:
				Literal(value):
					# log_trace("opcode: Literal {value}")
					write_symbol(table, symbol: value)
				Repeat(rep):    # Repeat previous symbol 3-6 times
					# log_trace("opcode: Repeat {rep}")
					write_symbol(table, symbol: 16)
					write_bits(n: 2, value: rep - 3)
				FewZeroes(rep):    # Repeat 3-10 zeroes
					# log_trace("opcode: FewZeroes {rep}")
					write_symbol(table, symbol: 17)
					write_bits(n: 3, value: rep - 3)
				ManyZeroes(rep):   # Repeat 11-138 zeroes
					# log_trace("opcode: ManyZeroes {rep}")
					write_symbol(table, symbol: 18)
					write_bits(n: 7, value: rep - 11)

	fn write_actions(pair: TreePair, actions: List[Action]):
		let first_table = create_table(tree: pair.first)
		let second_table = create_table(tree: pair.second)

		# 29 extra length bits:
		# TODO: support this as an immutable global variable
		let length_bits = [0, 0, 0, 0, 0, 0, 0, 0,  1,  1,  1,  1,  2,  2,  2,  2,  3,  3,  3,  3,  4,  4,  4,  4,   5,   5,   5,   5,   0]
		let length_base = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]

		# 30 extra distance bits:
		let dist_bits = [0, 0, 0, 0, 1, 1, 2, 2,  3,  3,  4,  4,  5,  5,  6,   6,   7,   7,   8,   8,   9,    9,    10,   10,   11,   11,   12,   12,    13,    13]
		let dist_base = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]

		for action in actions:
			case action:
				Literal(symbol):
					write_symbol(table: first_table, symbol)  # Emit byte as literal
				Copy(distance, length):
					var i = find_index(base: length_base, bits: length_bits, size: 29, value: length)
					write_symbol(table: first_table, symbol: 257 + i)
					if length_bits[i] > 0:
						write_bits(n: length_bits[i], value: length - length_base[i])

					i = find_index(base: dist_base, bits: dist_bits, size: 30, value: distance)
					write_symbol(table: second_table, symbol: i)
					if dist_bits[i] > 0:
						write_bits(n: dist_bits[i], value: distance - dist_base[i])

		write_symbol(table: first_table, symbol: 256)  # end of block

	fn create_actions() -> List[Action]:
		let actions: List[Action] = List()
		m_hash_table.clear()
		while m_index < m_data.len():
			var found_length = 0
			var found_position = 0
			if m_index + 2 < m_data.len():
				# Search for previous pattern
				let key = m_data.get(index: m_index) + m_data.get(index: m_index + 1) + m_data.get(index: m_index + 2)
				if m_hash_table.contains(key):
					for position in m_hash_table.get(key):
						# Maximize distance:
						if m_index - position > 32765:
							continue
						var i = 0
						while (i < 258) and (m_index + i < m_data.len()) and (m_data.get(index: position + i) == m_data.get(index: m_index + i)):
							i += 1
						if i > found_length:
							found_length = i
							found_position = position
					m_hash_table.get(key).append(m_index)
				else:
					m_hash_table.insert(key, value: list1(m_index))

			if found_length > 3:
				let distance = m_index - found_position
				# log_debug("Found match: position={found_position} distance={distance} - length={found_length}")
				actions.append(Action.Copy(distance, found_length))
				m_index += found_length
			else:
				actions.append(Action.Literal(m_data.get(index: m_index)))
				m_index += 1

			# Limit block size somewhat:
			if actions.len() > 60000:
				break
		actions

	# fn search_pattern(start: int):
	# 	let i = start
	# 	while m_data.get(index: i) == m_data.get(index: m_index):
	# 		i += 1

	fn no_compression():
		while m_index < m_data.len():
			var size = m_data.len() - m_index
			var last_block = 0
			if size > 4000:
				size = 4000
			else:
				last_block = 1
			write_uncompressed_block(size, last_block)

	fn write_uncompressed_block(size: int, last_block: int):
		log_trace("Size: {size}")

		write_block_header(last_block, btype: 0)
		m_bit_writer.flush()

		m_bit_writer.m_output.pack_u16_le(size)
		m_bit_writer.m_output.pack_u16_le(0xFFFF ^ size)

		var i = 0
		while i < size:
			m_bit_writer.m_output.append(m_data.get(index: m_index))
			m_index += 1
			i += 1

	fn write_symbol(table: HashMap[int,CodeEntry], symbol: int):
		encode_symbol(table, symbol, bit_writer: m_bit_writer)

	fn write_bits(n: int, value: int):
		m_bit_writer.write_bits(n, value)

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
		var len = read_u16_le()
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

		let code_lengths: Vector[int] = new_vector_of_size(size: 19, default: 0)
		var i = 0
		let clcidx = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
		while i < hclen:
			let clen = read_bits(3)
			let index = clcidx[i]
			code_lengths.set(index, value: clen)
			i += 1
		let tree = create_tree(lengths: code_lengths)

		# Read a fair amount of code lengths:
		let lengths: Vector[int] = new_vector()
		while lengths.len() < hlit + hdist:
			let symbol = decode_symbol(tree, bit_reader: m_bit_reader)
			# print("symbol={symbol}")
			var times = 0
			var L = 0
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
			var symbol = decode_symbol(tree: pair.first, bit_reader: m_bit_reader)
			# log_trace("Symbol: {symbol}")
			if symbol < 256:  # Literal byte
				emit_byte(symbol)
			elif symbol == 256:  # End-of-block
				break
			else:  # Length / distance combination
				assert(condition: symbol > 256, message: "value must be larger than 256 here: {symbol}")
				symbol -= 257

				assert(condition: symbol < 29, message: "Invalid length code: {symbol}")
				var length = read_bits(length_bits[symbol]) + length_base[symbol]

				symbol = decode_symbol(tree: pair.second, bit_reader: m_bit_reader)
				assert(condition: symbol < 30, message: "Invalid distance code: {symbol}")
				let distance = read_bits(dist_bits[symbol]) + dist_base[symbol]

				log_trace("length={length} distance={distance}")
				var index = m_output.len() - distance
				while length > 0:
					let value = m_output.get(index)
					emit_byte(value)
					index += 1
					length -= 1

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

struct TreePair:
	first: Tree
	second: Tree

fn create_tree(lengths: Vector[int]) -> Tree:
	# Given a set of lengths, calculate the Huffman tree.
	# A Huffman tree can be defined entirely by the bit lengths
	# of each symbol.

	# Step 1: count number of codes for each non-zero length
	var counts: [int] = zero_int_array(size: 17)

	for length in lengths:
		assert(condition: length < 17, message: "Length must be less than 17")
		counts[length] = counts[length] + 1

	# Step 2: determine start code for each bit length:
	var offsets: [int] = zero_int_array(size: 17)

	var bits = 1
	while bits < 16:
		offsets[bits + 1] = offsets[bits] + counts[bits]
		bits += 1

	# Step 3: Fill in table with used symbols:
	var symbols: [int] = zero_int_array(size: 288)

	var symbol = 0
	for length in lengths:
		if length > 0:
			symbols[offsets[length]] = symbol
			offsets[length] = offsets[length] + 1
		symbol += 1

	Tree:
		counts
		symbols

fn create_fixed_trees() -> TreePair:
	let first = create_tree(lengths: create_fixed_literal_lengths())
	let second = create_tree(lengths: create_fixed_distance_lengths())
	TreePair(first, second)

fn create_fixed_literal_lengths() -> Vector[int]:
	let lengths: Vector[int] = new_vector()
	var symbol = 0
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
	lengths

fn create_fixed_distance_lengths() -> Vector[int]:
	let lengths: Vector[int] = new_vector()
	var symbol = 0
	while symbol < 32:
		lengths.append(5)
		symbol += 1
	lengths
