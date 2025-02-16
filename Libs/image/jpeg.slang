"""
JPEG handling.

See also: https://www.w3.org/Graphics/JPEG/itu-t81.pdf

Zig zag pattern:
0,  1,  5,  6,  14, 15, 27, 28
2,  4,  7,  13, 16, 26, 29, 42
3,  8,  12, 17, 25, 30, 41, 43
9,  11, 18, 24, 31, 40, 44, 53
10, 19, 23, 32, 39, 45, 52, 54
20, 22, 33, 38, 46, 51, 55, 60
21, 34, 37, 47, 50, 56, 59, 61
35, 36, 48, 49, 57, 58, 62, 63
"""

import math
from utils import panic, unimplemented, log_info, log_debug, assert
from vectype import Vector, new_vector
from bytes import ByteReader, Bytes, ByteArray
from huffman import BitReader, Tree, decode_symbol, zero_int_array
from hashmap import HashMap, new_hashmap_int
from image import Image, new_black_image, Pixel, new_empty_image
from qoi import read_whole_file_as_bytes

pub fn read_jpg_from_file(filename: str) -> Image:
	log_info("Reading JPG from {filename}")
	let data = read_whole_file_as_bytes(filename)
	read_jpeg_from_data(data)

fn read_jpeg_from_data(data: Bytes) -> Image:
	let decoder = JpegDecoder(m_reader: data.into_reader())
	decoder.read_segments()
	decoder.get_image()

class JpegDecoder:
	var m_reader: ByteReader
	var m_huffman_tables: HashMap[int, Tree] = new_hashmap_int()
	var m_quant: HashMap[int, Bytes] = new_hashmap_int()
	var m_width: int = 0
	var m_height: int = 0
	var m_components: Vector[Component] = new_vector()
	var m_image: Image = new_empty_image()
	var m_idct: IDCT = new_idct_table()

	pub fn read_segments():
		while not at_end():
			read_segment()

	pub fn get_image() -> Image:
		m_image

	fn read_segment():
		""" Read a single JPEG segment """
		let x = read_byte()
		if x != 0xff:
			panic("Expected 0xff")

		let kind = read_byte()
		if kind == 0xD8: # Start of image
			log_debug("SOI")
		elif kind == 0xE0: # JFIF APP0 marker
			let size = read_u16() - 2
			log_debug("APP0 marker of size {size}")
			let payload = read_data(size)
		elif kind >= 0xE1 and kind <= 0xEF: # APPn marker
			let size = read_u16() - 2
			log_debug("APPn marker of size {size}")
			let payload = read_data(size)
		elif kind == 0xC0: # SOF0 Start of frame
			start_of_frame()
		elif kind == 0xC4: # DHT Define huffman table
			huffman_table()
		elif kind == 0xDA: # SOS start of scan
			start_of_scan()
		elif kind == 0xDB: # DQT define quantization table
			define_quantization_table()
		elif kind == 0xD9: # End of image
			log_debug("EOI")
		else:
			unimplemented("Marker type: {kind}")

	fn huffman_table():
		let size = read_u16() - 2
		let header = read_byte()
		log_debug("DHT of size {size} and header {header}")
		# let number = header & 0xf
		# let ty = (header >> 4) & 1
		let lengths = read_data(size: 16)
		size -= 17
		let n_symbols = 0
		for length in lengths:
			n_symbols += length
		assert(condition: n_symbols > 0, message: "n_symbols must be larger than 0.")
		let counts = zero_int_array(size: 17)
		let symbols = zero_int_array(size: n_symbols)
		let bitsize = 1
		let offset = 0
		for length in lengths:
			let symbols_data = read_data(size: length)
			size -= length
			counts[bitsize] = length
			bitsize += 1
			for symbol in symbols_data:
				symbols[offset] = symbol
				offset += 1
		assert(condition: size == 0, message: "Size should be 0, not {size}")
		let tree = Tree(counts, symbols)
		m_huffman_tables.insert(key: header, value: tree)

	fn define_quantization_table():
		let size = read_u16() - 2
		let header = read_byte()
		log_debug("DQT of size {size} header={header}")
		size -= 1
		let payload = read_data(size)
		m_quant.insert(key: header, value: payload)

	fn start_of_frame():
		let size = read_u16() - 2
		log_debug("SOF0 of size {size}")
		let header = read_byte()
		m_height = read_u16()
		m_width = read_u16()
		let components = read_byte()
		log_debug("Size: {m_width}x{m_height} with {components} components")
		m_image = new_black_image(width: m_width, height: m_height)
		size -= 6
		assert(condition: size == components * 3, message: "Should have 3 bytes per component")
		let i = 0
		while i < components:
			let id = read_byte()
			let samp = read_byte()
			let qid = read_byte()
			log_debug("component {i}: id={id} samp={samp} qid={qid}")
			m_components.append(Component(qid, dc_coeff: 0))
			size -= 3
			i += 1

	fn start_of_scan():
		let size = read_u16() - 2
		log_debug("SOS of size {size}")
		let payload = read_data(size)

		let data = read_non_ff00()
		log_debug("data size = {data.len()}")
		let bit_reader = BitReader(m_reader: data.into_reader(), m_reverse: true)

		# Loop over image blocks!
		let b_y = 0
		let b_y_size = (m_height + 7) / 8
		let b_x_size = (m_width + 7) / 8
		while b_y < b_y_size:
			let b_x = 0
			while b_x < b_x_size:
				# log_debug("x={b_x} y={b_y}")
				let lum = build_matrix(idx: 0, bit_reader, component: m_components[0])
				let cb = build_matrix(idx: 1, bit_reader, component: m_components[1])
				let cr = build_matrix(idx: 1, bit_reader, component: m_components[2])
				draw_block(x: b_x * 8, y: b_y * 8, lum, cb, cr)
				b_x += 1
			b_y += 1

		# Encoded data is located here!

	fn read_non_ff00() -> Bytes:
		# Scan data for 0xFF 0x..
		let data2 = ByteArray()
		loop:
			let b1 = m_reader.peek_byte(ahead: 0)
			if b1 == 0xFF:
				let b2 = m_reader.peek_byte(ahead: 1)
				if b2 == 0:
					let x = read_byte()
					let discard = read_byte()
					data2.append(x)
				else:
					break
			else:
				let x = read_byte()
				data2.append(x)
		data2.to_bytes()

	fn build_matrix(idx: int, bit_reader: BitReader, component: Component) -> [int]:
		""" Extract an 8x8 matrix from bits """
		let tree1 = m_huffman_tables.get(key: idx)
		let tree2 = m_huffman_tables.get(key: 16 + idx)
		let quant = m_quant.get(key: component.qid)

		let code = decode_symbol(tree: tree1, bit_reader)
		# log_debug("a = {code}")
		let bits = bit_reader.read_bits(n: code)
		let dc_coeff = decode_number(code, bits) + component.dc_coeff
		component.dc_coeff = dc_coeff
		let res = zero_int_array(size: 64)
		res[0] = dc_coeff * quant[0]

		let index = 1
		while index < 64:
			let code = decode_symbol(tree: tree2, bit_reader)
			# log_debug("b = {code}")
			if code == 0:
				break
			if code > 15:
				index += code >> 4
				code = code & 15

			let bits = bit_reader.read_bits(n: code)
			if index < 64:
				let ac_coeff = decode_number(code, bits)
				res[index] = ac_coeff * quant[index]
				index += 1
		res = zigzag(data: res)
		perform_idct(data: res, idct: m_idct)

	fn draw_block(x: int, y: int, lum: [int], cb: [int], cr: [int]):
		""" Put 8x8 block into the pixels of the image """
		let xx = 0
		while xx < 8:
			let yy = 0
			while yy < 8:
				if x + xx < m_width and y + yy < m_height:
					let pixel = m_image.get_pixel(x: x + xx, y: y + yy)
					let i = yy * 8 + xx
					color_conversion(lum: lum[i], cb: cb[i], cr: cr[i], pixel)
				yy += 1
			xx += 1

	fn at_end() -> bool:
		m_reader.at_end()

	fn read_byte() -> int:
		m_reader.read_byte()

	fn read_u16() -> int:
		m_reader.read_u16_be()

	fn read_data(size: int) -> Bytes:
		m_reader.read_bytes(size)

fn zigzag(data: [int]) -> [int]:
	let pattern = [0,  1,  5,  6,  14, 15, 27, 28, 2,  4,  7,  13, 16, 26, 29, 42, 3,  8,  12, 17, 25, 30, 41, 43, 9,  11, 18, 24, 31, 40, 44, 53, 10, 19, 23, 32, 39, 45, 52, 54, 20, 22, 33, 38, 46, 51, 55, 60, 21, 34, 37, 47, 50, 56, 59, 61, 35, 36, 48, 49, 57, 58, 62, 63]
	let res = zero_int_array(size: 64)
	# log_debug("zigzag")
	let i = 0
	while i < 64:
		res[i] = data[pattern[i]]
		i += 1
	res

struct IDCT:
	precision: int
	table: [float]

fn new_idct_table() -> IDCT:
	# log_debug("new_idct_table")
	let precision = 8
	let table = [precision * precision : float]
	let u = 0
	while u < precision:
		let x = 0
		while x < precision:
			# log_debug("new_idct_table {x} {u}")
			let c = math.cos(((2.0 * x + 1.0) * u * math.pi) / 16.0)
			if u == 0:
				# TODO: sqrt(2) blocks
				# c = c / math.sqrt(2.0)
				c = c / 1.414213562373
			table[u * precision + x] = c
			x += 1
		u += 1
	IDCT(precision, table)

fn perform_idct(data: [int], idct: IDCT) -> [int]:
	""" inverse discrete cosine transformation """
	# log_debug("idct")
	let res = zero_int_array(size: 64)
	let x = 0
	while x < 8:
		let y = 0
		while y < 8:
			let sum = 0.0
			let u = 0
			while u < idct.precision:
				let v = 0
				while v < idct.precision:
					sum += data[v * 8 + u] * idct.table[u * 8 + x] * idct.table[v * 8 + y]
					v += 1
				u += 1
			res[y * 8 + x] = int(sum / 4.0)
			y += 1
		x += 1
	res

struct Component:
	qid: int
	dc_coeff: int

fn clamp(value?: float) -> int:
	if value < 0.0:
		0
	elif value < 255.0:
		int(value)
	else:
		255

fn color_conversion(lum: int, cb: int, cr: int, pixel: Pixel):
	""" Convert YCbCr to RGB """
	let red = cr * (2 - 2 * 0.299) + lum
	let blue = cb * (2 - 2 * 0.114) + lum
	let green = (lum - 0.114 * blue - 0.299 * red) / 0.587
	pixel.red = clamp(red + 128)
	pixel.green = clamp(green + 128)
	pixel.blue = clamp(blue + 128)

fn decode_number(code: int, bits: int) -> int:
	"""
	code = amount of bits
	bits = the bit value
	Mapping:
	bits | values
	  2  | -3,-2,2,3
	  3  | -7..-4,4..7
	  4  | -15..-8,8..15
	   ...
	"""
	if code == 0:
		return 0

	let m = 1 << (code - 1)
	if bits >= m:
		bits
	else:
		bits - (2 * m - 1)
