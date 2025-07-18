"""
PNG read / write routines

See RFC 2083
"""

from utils import unimplemented, panic, assert, log_warning, log_debug
from math import abs, modulo
from bytes import Bytes, ByteReader, bytes_from_ascii, bytes_from_hex_text, ByteArray, bytes_to_ascii, new_bytes
from gzip import calc_crc32, zlib_decompress, zlib_compress
from qoi import read_whole_file_as_bytes, write_bytes_to_file
from image import Image, new_image, Pixel

pub fn read_png_from_file(filename: str) -> Image:
	log_debug("Loading PNG from {filename}")
	let data = read_whole_file_as_bytes(filename)
	read_png_from_bytes(data)

fn read_png_from_bytes(data: Bytes) -> Image:
	let reader = data.into_reader()
	read_png_from_stream(reader)

fn read_png_from_stream(reader: ByteReader) -> Image:
	let decoder = PngDecoder(m_byte_reader: reader)
	decoder.read_image()

pub fn write_png_to_file(image: Image, filename: str):
	log_debug("Writing PNG image to {filename}")
	let encoder = PngEncoder()
	let data = encoder.write(image)
	write_bytes_to_file(filename, data)

# fn write_png_to_stream(image: Image, writer: ByteArray):
#     #PngEncoder
#     unimplemented("write_png_to_stream")

class PngDecoder:
	var m_byte_reader: ByteReader

	pub fn read_image() -> Image:
		let signature = read_bytes(8)
		# let expected_signature = bytes_from_hex_text(text: "89 50 4e 47 0d 0a 1a 0a")
		assert(condition: signature.as_hex() == "89504E470D0A1A0A", message: "Invalid signature: {signature.as_hex()}")

		let type_ihdr = chunk_type_code(name: "IHDR")
		let type_idat = chunk_type_code(name: "IDAT")
		let type_iend = chunk_type_code(name: "IEND")
		# let type_gama = chunk_type_code(name: "gAMA")
		# let type_gama = chunk_type_code(name: "sRGB")

		var idat: Bytes = new_bytes()
		var width = 0
		var height = 0
		var bpp = 0
		var colortype = 0

		# Loop over chunks in PNG:
		loop:
			let chunk = read_chunk()
			if chunk.chunk_type == type_ihdr:
				log_debug("IHDR chunk")
				let r = chunk.data.into_reader()
				width = r.read_u32_be()
				height = r.read_u32_be()

				let bitdepth = r.read_byte()
				colortype = r.read_byte()
				let compression = r.read_byte()
				let filter_method = r.read_byte()
				let interlace_method = r.read_byte()
				log_debug("width={width} height={height} bitdepth={bitdepth} colortype={colortype}")
				log_debug("compression={compression} filter_method={filter_method} interlace_method={interlace_method}")
				assert(condition: bitdepth == 8, message: "Only support 8 bits depth")
				# color types:
				# 0 = grayscale
				# 2 = rgb
				# 3 = indexed
				# 4 = grayscal and alpha
				# 6 = rgb + alpha

				if colortype == 2: # rgb
					bpp = 3
				elif colortype == 6: # rgb a
					bpp = 4
				else:
					panic("Unsupported color type: {colortype}")

				# compression type 0 --> zlib deflate format
				assert(condition: compression == 0, message: "compression must be 0")

				# Filter method 0, means 5 pre defined filter types
				assert(condition: filter_method == 0, message: "filter must be 0")
				assert(condition: interlace_method == 0, message: "Only support no interlace")

			elif chunk.chunk_type == type_idat:
				log_debug("IDAT chunk")
				idat = idat.concat(other: chunk.data)

			elif chunk.chunk_type == type_iend:
				log_debug("IEND chunk")
				break
			else:
				let type_data = ByteArray()
				type_data.pack_u32_be(chunk.chunk_type)
				log_warning("Unsupported chunk type: {bytes_to_ascii(data: type_data.to_bytes())}")


		# Post processing!
		# Decompress data:
		let data2 = zlib_decompress(data: idat)
		log_debug("Decompressed {data2.len()} bytes")
		let data3 = post_filter(data: data2, width, height, bpp)
		let image = new_image(width, height)
		to_pixels(data: data3, image, colortype)
		image

	fn read_chunk() -> Chunk:
		let chunk_length = read_u32_be()
		let chunk_type = read_u32_be()
		let data = read_bytes(chunk_length)
		let crc_data = ByteArray()
		crc_data.pack_u32_be(chunk_type)
		crc_data.extend(data)
		let chunk_crc = read_u32_be()
		# check crc:
		let crc = calc_crc32(data: crc_data.to_bytes())
		assert(condition: crc == chunk_crc, message: "CRC mismatch: {crc} != {chunk_crc}")
		Chunk(chunk_type, data)

	fn read_bytes(size?: int) -> Bytes:
		m_byte_reader.read_bytes(size)

	fn read_u32_be() -> int:
		m_byte_reader.read_u32_be()

class PngEncoder:
	var m_writer: ByteArray = ByteArray()

	pub fn write(image: Image) -> Bytes:
		let signature = bytes_from_hex_text(text: "89504E470D0A1A0A")
		m_writer.extend(signature)

		let width = image.width
		let height = image.height
		let bpp = 3

		# Write IHDR chunk
		let out = ByteArray()
		out.pack_u32_be(width)
		out.pack_u32_be(height)
		out.append(8) # bit depth
		out.append(2) # color type (2 = rgd)
		out.append(0) # compression type
		out.append(0) # filter method
		out.append(0) # interlace method
		let ihdr_chunk = Chunk(chunk_type: chunk_type_code(name: "IHDR"), data: out.to_bytes())
		write_chunk(chunk: ihdr_chunk)

		# Write IDAT chunk
		let data = pixels_to_buffer(image)
		let data2 = encode_filter(data, width, height, bpp)
		log_debug("Compressing {data2.len()} bytes")
		let data3 = zlib_compress(data: data2)
		let idat_chunk = Chunk(chunk_type: chunk_type_code(name: "IDAT"), data: data3)
		write_chunk(chunk: idat_chunk)

		# Write IEND chunk
		let iend_chunk = Chunk(chunk_type: chunk_type_code(name: "IEND"), data: new_bytes())
		write_chunk(chunk: iend_chunk)
		m_writer.to_bytes()

	fn write_chunk(chunk: Chunk):
		# Write chunk to output.
		let crc_data = ByteArray()
		crc_data.pack_u32_be(chunk.chunk_type)
		crc_data.extend(chunk.data)
		let crc = calc_crc32(data: crc_data.to_bytes())

		m_writer.pack_u32_be(chunk.data.len())
		m_writer.pack_u32_be(chunk.chunk_type)
		m_writer.extend(chunk.data)
		m_writer.pack_u32_be(crc)

fn pixels_to_buffer(image: Image) -> Bytes:
	let out = ByteArray()
	var scanline = 0
	while scanline < image.height:
		var x = 0
		while x < image.width:
			let pixel = image.pixels.get(index: scanline * image.width + x)
			out.append(pixel.red)
			out.append(pixel.green)
			out.append(pixel.blue)

			x += 1
		scanline += 1
	out.to_bytes()

fn to_pixels(data: Bytes, image: Image, colortype: int):
	var scanline = 0
	var index = 0
	while scanline < image.height:
		var x = 0
		while x < image.width:
			let red = data.get(index)
			index += 1
			let green = data.get(index)
			index += 1
			let blue = data.get(index)
			index += 1

			var alpha = 0xFF
			if colortype == 6:
				alpha = data.get(index)
				index += 1

			# Push pixel:
			let pixel = Pixel(red, green, blue, alpha)
			image.pixels.append(pixel)
			x += 1
		scanline += 1

fn encode_filter(data: Bytes, width: int, height: int, bpp: int) -> Bytes:
	# Apply filtering as encoding step
	let out = ByteArray()
	let bytes_per_line = bpp * width
	var scanline = 0
	var index = 0
	while scanline < height:
		# Idea: try all filter types, and select filtered line with the lowest entropy
		out.append(0) # no-op filter type
		var x = 0
		while x < bytes_per_line:
			let value = data.get(index)
			index += 1
			out.append(value)
			x += 1
		scanline += 1

	let filtered = out.to_bytes()
	let expected_data_size = (width * bpp + 1) * height
	assert(condition: filtered.len() == expected_data_size, message: "Expected {expected_data_size}, but created {filtered.len()}")
	filtered

fn post_filter(data: Bytes, width: int, height: int, bpp: int) -> Bytes:
	# Perform post filtering on a byte basis.
	# Note that we have no notion of bit depth or color space at this point.

	let expected_data_size = (width * bpp + 1) * height
	assert(condition: data.len() == expected_data_size, message: "PNG data size mismatch, expected {expected_data_size}, but got {data.len()}")

	var scanline = 0
	var index = 0
	let bytes_per_line = bpp * width
	let out = ByteArray()
	while scanline < height:
		let filter_type = data.get(index)
		index += 1
		# log_debug("Filter type: {filter_type}")

		var x = 0
		while x < bytes_per_line:
			var value = data.get(index)
			index += 1

			# filter type:
			# 0 = None -> no delta
			# 1 = Sub -> diff to pixel to the left
			# 2 = Up -> diff to pixel up
			# 3 = Average
			# 4 = Paeth
			if filter_type == 0: # No-op
				pass
			elif filter_type == 1: # Diff to left pixel
				if x >= bpp:
					let left_value = out.get(index: scanline * bytes_per_line + x - bpp)
					value = modulo(value: value + left_value, divisor: 256)
			elif filter_type == 2: # Diff to above pixel
				if scanline > 0:
					let above_value = out.get(index: (scanline - 1) * bytes_per_line + x)
					value = modulo(value: value + above_value, divisor: 256)
			elif filter_type == 3:  # Average
				let left_value = if x >= bpp:
					out.get(index: scanline * bytes_per_line + x - bpp)
				else:
					0
				let above_value = if scanline > 0:
					out.get(index: (scanline - 1) * bytes_per_line + x)
				else:
					0
				value = modulo(value: value + average(a: left_value, b: above_value), divisor: 256)
			elif filter_type == 4:  # Paeth
				var left_value = 0
				if x >= bpp:
					left_value = out.get(index: scanline * bytes_per_line + x - bpp)
				var above_value = 0
				if scanline > 0:
					above_value = out.get(index: (scanline - 1) * bytes_per_line + x)
				var left_up_value = 0
				if (x >= bpp) and (scanline > 0):
					left_up_value = out.get(index: (scanline - 1) * bytes_per_line + x - bpp)
				value = modulo(value: value + paeth_predictor(a: left_value, b: above_value, c: left_up_value), divisor: 256)
			else:
				unimplemented("Filter type: {filter_type}")

			out.append(value)
			x += 1
		scanline += 1
	out.to_bytes()

fn average(a: int, b: int) -> int:
	(a + b) / 2

fn paeth_predictor(a: int, b: int, c: int) -> int:
	let p = a + b - c
	let pa = abs(p - a)
	let pb = abs(p - b)
	let pc = abs(p - c)
	if (pa <= pb) and (pa <= pc):
		a
	elif pb <= pc:
		b
	else:
		c

struct Chunk:
	chunk_type: int
	data: Bytes

fn chunk_type_code(name: str) -> int:
	let reader = bytes_from_ascii(text: name).into_reader()
	reader.read_u32_be()
