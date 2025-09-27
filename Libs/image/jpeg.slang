"""
JPEG handling.

See also: https://www.w3.org/Graphics/JPEG/itu-t81.pdf

"""

import math
from utils import panic, unimplemented, assert
from logging import log_info, log_debug
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
		elif kind == 0xC0: # SOF0 Start of frame, baseline DCT
			start_of_frame(n: 0)
		elif kind == 0xC2: # SOF2 Start of frame, progressive DCT
			start_of_frame(n: 2)
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
		var size = read_u16() - 2
		let header = read_byte()
		log_debug("DHT of size {size} and header {header}")
		# let number = header & 0xf
		# let ty = (header >> 4) & 1
		let lengths = read_data(size: 16)
		size -= 17
		var n_symbols = 0
		for length in lengths:
			n_symbols += length
		assert(condition: n_symbols > 0, message: "n_symbols must be larger than 0.")
		var counts = zero_int_array(size: 17)
		var symbols = zero_int_array(size: n_symbols)
		var bitsize = 1
		var offset = 0
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
		var size = read_u16() - 2
		let header = read_byte()
		log_debug("DQT of size {size} header={header}")
		size -= 1
		let payload = read_data(size)
		m_quant.insert(key: header, value: payload)

	fn start_of_frame(n: int):
		""" Baseline DCT """
		var size = read_u16() - 2
		log_debug("SOF{n} of size {size}")
		let P = read_byte()
		assert(condition: P == 8, message: "Only 8 bit precision supported")
		m_height = read_u16()  # Y
		m_width = read_u16()  # X
		let Nf = read_byte()
		log_debug("Size: {m_width}x{m_height} with {Nf} components")
		m_image = new_black_image(width: m_width, height: m_height)
		size -= 6
		assert(condition: size == Nf * 3, message: "Should have 3 bytes per component")
		var i = 0
		while i < Nf:
			let C = read_byte()
			let samp = read_byte()
			let H = samp >> 4
			let V = samp & 0xF
			let qid = read_byte()
			log_debug("component {i}: C={C} samp={samp} H={H} V={V} qid={qid}")
			m_components.append(Component(C, H, V, qid, dc_coeff: 0, T_dc: 0, T_ac: 0))
			size -= 3
			i += 1

	fn start_of_scan():
		var size = read_u16() - 2
		log_debug("SOS of size {size}")
		let Ns = read_byte()
		log_debug("Number of components in scan: {Ns}")
		size -= 1
		assert(condition: Ns * 2 + 3 == size, message: "Invalid start of scan size: {size}")
		assert(condition: Ns == m_components.len(), message: "Component amount mismatch")
		var i = 0
		while i < Ns:
			let Cs = read_byte()
			let Tda = read_byte() # DC and AC Huffman table selectors
			log_debug("Scan component: Cs={Cs} Tda={Tda}")
			let component = m_components.get(index: i)
			assert(condition: Cs == component.C, message: "Component ID mismatch")
			component.T_dc = Tda >> 4
			component.T_ac = Tda & 0xF
			size -= 2
			i += 1

		let Ss = read_byte()
		let Se = read_byte()
		log_debug("Ss={Ss} Se={Se}")
		assert(condition: Ss == 0, message: "Ss must be 0")
		assert(condition: Se == 63, message: "Se must be 63")
		let Ahl = read_byte()
		size -= 3
		assert(condition: size == 0, message: "All bytes should be processed")

		let data = read_non_ff00()
		log_debug("data size = {data.len()}")
		let bit_reader = BitReader(m_reader: data.into_reader(), m_reverse: true)

		# Determine minimal coding unit (MCU)
		var max_H = 1
		var max_V = 1
		for component in m_components:
			if component.H > max_H:
				max_H = component.H
			if component.V > max_V:
				max_V = component.V
		let mcu_width = 8 * max_H
		let mcu_height = 8 * max_V

		# Loop over image MCU's!
		log_debug("MCU size {mcu_width}x{mcu_height}")
		var b_y = 0
		let b_y_size = (m_height + mcu_height - 1) / mcu_height
		let b_x_size = (m_width + mcu_width - 1) / mcu_width
		while b_y < b_y_size:
			var b_x = 0
			while b_x < b_x_size:
				# log_debug("x={b_x} y={b_y}")
				# Read 1 MCU:
				let mcu: Vector[[int]] = new_vector()
				for component in m_components:
					mcu.append(read_component_mcu(bit_reader, component, mcu_width, mcu_height))
				draw_block(x: b_x * mcu_width, y: b_y * mcu_height, mcu_width, mcu_height, mcu)
				b_x += 1
			b_y += 1

		assert(condition: bit_reader.m_reader.at_end(), message: "Bits must be exhausted")

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

	fn read_component_mcu(bit_reader: BitReader, component: Component, mcu_width: int, mcu_height: int) -> [int]:
		""" Read a single MCU data array """
		var block = zero_int_array(size: mcu_width * mcu_height)
		let upx = mcu_width / (component.H * 8) # Upsample factor x
		let upy = mcu_height / (component.V * 8)

		var sby = 0  # sub block y
		while sby < component.V:
			var sbx = 0
			while sbx < component.H:
				let m = build_matrix(bit_reader, component)

				# Paste block in proper place into matrix
				var mx = 0
				while mx < 8:
					var my = 0
					while my < 8:
						let val = m[my * 8 + mx]
						# x,y in block:
						let x = (sbx * 8 + mx) * upx
						let y = (sby * 8 + my) * upy

						# upsample value:
						var dx = 0
						while dx < upx:
							var dy = 0
							while dy < upy:
								block[(y + dy) * mcu_width + x + dx] = val
								dy += 1
							dx += 1

						my += 1
					mx += 1
				sbx += 1
			sby += 1
		block

	fn build_matrix(bit_reader: BitReader, component: Component) -> [int]:
		""" Extract an 8x8 matrix from bits """
		let dc_table = m_huffman_tables.get(key: component.T_dc)
		let ac_table = m_huffman_tables.get(key: 16 + component.T_ac)
		let quant = m_quant.get(key: component.qid)

		let code = decode_symbol(tree: dc_table, bit_reader)
		# log_debug("a = {code}")
		let bits = bit_reader.read_bits(n: code)
		let dc_coeff = decode_number(code, bits) + component.dc_coeff
		component.dc_coeff = dc_coeff
		var res = zero_int_array(size: 64)
		res[0] = dc_coeff * quant[0]

		var index = 1
		while index < 64:
			var code = decode_symbol(tree: ac_table, bit_reader)
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

	fn draw_block(x: int, y: int, mcu_width: int, mcu_height: int, mcu: Vector[[int]]):
		""" Put 8x8 block into the pixels of the image """
		assert(condition: mcu.len() == 3, message: "Expect 3 components")
		# assert(condition: datas.len() == 3, message: "Expect 3 components")
		let lum_data = mcu[0]
		let cb_data = mcu[1]
		let cr_data = mcu[2]
		var xx = 0
		while xx < mcu_width:
			var yy = 0
			while yy < mcu_height:
				if x + xx < m_width and y + yy < m_height:
					let pixel = m_image.get_pixel(x: x + xx, y: y + yy)
					let i = yy * mcu_width + xx
					let lum = lum_data[i]
					let cb = cb_data[i]
					let cr = cr_data[i]
					color_conversion(lum, cb, cr, pixel)
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
	"""
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
	let pattern = [0,  1,  5,  6,  14, 15, 27, 28, 2,  4,  7,  13, 16, 26, 29, 42, 3,  8,  12, 17, 25, 30, 41, 43, 9,  11, 18, 24, 31, 40, 44, 53, 10, 19, 23, 32, 39, 45, 52, 54, 20, 22, 33, 38, 46, 51, 55, 60, 21, 34, 37, 47, 50, 56, 59, 61, 35, 36, 48, 49, 57, 58, 62, 63]
	var res = zero_int_array(size: 64)
	# log_debug("zigzag")
	var i = 0
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
	var table = [precision * precision : float]
	let sqrt_2 = math.sqrt(2.0)
	var u = 0
	while u < precision:
		var x = 0
		while x < precision:
			# log_debug("new_idct_table {x} {u}")
			var c = math.cos(((2.0 * x + 1.0) * u * math.pi) / 16.0)
			if u == 0:
				c = c / sqrt_2
			table[u * precision + x] = c
			x += 1
		u += 1
	IDCT(precision, table)

fn perform_idct(data: [int], idct: IDCT) -> [int]:
	""" inverse discrete cosine transformation """
	# log_debug("idct")
	var res = zero_int_array(size: 64)
	var x = 0
	while x < 8:
		var y = 0
		while y < 8:
			var sum = 0.0
			var u = 0
			while u < idct.precision:
				var v = 0
				while v < idct.precision:
					sum += data[v * 8 + u] * idct.table[u * 8 + x] * idct.table[v * 8 + y]
					v += 1
				u += 1
			res[y * 8 + x] = int(sum / 4.0)
			y += 1
		x += 1
	res

struct Component:
	C: int  # Identifier
	H: int  # Horizontal sampling
	V: int  # Vertical sampling
	qid: int  # Quantization table to use for this component
	dc_coeff: int
	T_dc: int # DC Huffman table id
	T_ac: int # AC Huffman table id

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
