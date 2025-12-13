
#
# encoder / decoder for the QOI (quite ok image) format.
#
# See also: https://qoiformat.org/
# https://qoiformat.org/qoi-specification.pdf

import std
from utils import panic, assert
from logging import log_info
from bytes import Bytes, ByteReader, ByteArray, bytes_to_ascii, bytes_from_ascii
from vectype import Vector, new_vector
from image import Image, new_image, new_empty_image, Pixel, new_pixel, ColorMode, copy_pixel

pub fn read_whole_file_as_bytes(filename: str) -> Bytes:
	# Helper to read in a whole file into a bytes object in memory
	let handle = std.file_open(filename, mode: "rb")
	let ba = ByteArray()
	let buffer: [uint8] = [200 : uint8]
	loop:
		let res = std.file_read_n_bytes(handle, buffer, bufsize: 200)
		if res > 0:
			var i = 0
			while i < res:
				ba.append(int(buffer[i]))
				i += 1
		else:
			break
	std.file_close(handle)

	ba.to_bytes()

pub fn write_bytes_to_file(filename: str, data: Bytes):
	let handle = std.file_open(filename, mode: "wb")
	var buffer: [uint8] = [200 : uint8]
	var i = 0
	var j = 0
	while i < data.len():
		buffer[j] = uint8(data[i])
		j += 1
		if j == 200:
			let x = std.file_write_n_bytes(handle, buffer, bufsize: j)
			assert(condition: x == j, message: "file_write_n_bytes failed")
			j = 0
		i += 1

	if j > 0:
		let x = std.file_write_n_bytes(handle, buffer, bufsize: j)
		assert(condition: x == j, message: "file_write_n_bytes failed")

	std.file_close(handle)

# TODO: support constants:
# QOI_OP_RGB = 0b1111_1110
# QOI_OP_RGBA = 0b1111_1111

pub fn read_qoi_from_file(filename: str) -> Image:
	let data = read_whole_file_as_bytes(filename)
	let reader = QoiReader(m_reader: data.into_reader())
	reader.read_image()

pub fn write_qoi_to_file(image: Image, filename: str):
	# Write image as QOI file.
	let writer = QoiWriter()
	let data = writer.write(image)
	write_bytes_to_file(filename, data)

class QoiReader:
	var m_reader: ByteReader
	var m_array: Vector[Pixel] = new_vector()
	var m_image: Image = new_empty_image()
	var m_width: int = 0
	var m_height: int = 0
	var m_x: int = 0
	var m_y: int = 0

	pub fn read_image() -> Image:
		# let f = std.open_binary(filename)
		let magic = bytes_to_ascii(data: read_bytes(4))
		assert(condition: magic == "qoif", message: "Not a QOI image")

		# let magic = header[0,4]  # TODO: support [0:4]?
		m_width = m_reader.read_u32_be()
		m_height = m_reader.read_u32_be()
		let channels = read_byte()
		let colorspace = read_byte()
		log_info("Header: magic={magic} width={m_width} height={m_height}")

		m_image = new_image(width: m_width, height: m_height, mode: ColorMode.ColorAlpha())

		var i = 0
		while i < 64:
			m_array.append(new_pixel())
			i += 1

		let pixel: Pixel = new_pixel()
		pixel.red = 0
		pixel.green = 0
		pixel.blue = 0
		pixel.alpha = 0xFF

		var dr = 0
		var dg = 0
		var db = 0
		while (m_y * m_width + m_x) < m_width * m_height:
			let tag8 = read_byte()
			switch tag8:
				0b11111110:   # QOI_OP_RGB
					# TODO: support many unpack: r, g, b = read(3)
					pixel.red = read_byte()
					pixel.green = read_byte()
					pixel.blue = read_byte()
					put_pixel(pixel)
				0b11111111:  # QOI_OP_RGBA
					pixel.red = read_byte()
					pixel.green = read_byte()
					pixel.blue = read_byte()
					pixel.alpha = read_byte()
					put_pixel(pixel)
			else:
				# Check top 2 bits:
				let tag2 = tag8 >> 6
				switch tag2:
					0b00:  # QOI_OP_INDEX
						let index = tag8 & 0x3F
						let pixel2: Pixel = m_array[index]
						put_pixel(pixel: pixel2)
					0b01: # QOI_OP_DIFF
						dr = ((tag8 >> 4) & 3) - 2
						dg = ((tag8 >> 2) & 3) - 2
						db = (tag8 & 3) - 2
						pixel.red = wrap8(pixel.red + dr)
						pixel.green = wrap8(pixel.green + dg)
						pixel.blue = wrap8(pixel.blue + db)
						put_pixel(pixel)
					0b10:  # QOI_OP_LUMA
						dg = (tag8 & 0x3F) - 32
						let x = read_byte()
						dr = (((x >> 4) & 0xF) - 8) + dg
						db = ((x & 0xF) - 8) + dg
						pixel.red = wrap8(pixel.red + dr)
						pixel.green = wrap8(pixel.green + dg)
						pixel.blue = wrap8(pixel.blue + db)
						put_pixel(pixel)
					0b11:  # QOI_OP_RUN
						let length = (tag8 & 0x3F) + 1
						var i = 0
						while i < length:
							put_pixel(pixel)
							i += 1
				else:
					panic("read_image: Invalid opcode: {tag2}")
				# std.print("Pixel: {r} {g} {b} {a}")
		m_image

	fn put_pixel(pixel: Pixel):
		# std.print("Pixel: {r} {g} {b} {a}")
		let index = (pixel.red * 3 + pixel.green * 5 + pixel.blue * 7 + pixel.alpha * 11) % 64
		copy_pixel(dst: m_array.get(index), src: pixel)
		m_image.set_pixel(x: m_x, y: m_y, pixel)
		m_x += 1
		if m_x >= m_width:
			m_x = 0
			m_y += 1

	fn read_bytes(size?: int) -> Bytes:
		m_reader.read_bytes(size)

	fn read_byte() -> int:
		m_reader.read_byte()

fn wrap8(value?: int) -> int:
	# Implement 8 bit wrapping
	while value < 0:
		value += 256
	while value > 255:
		value -= 256
	value

class QoiWriter:
	var m_writer: ByteArray = ByteArray()

	pub fn write(image: Image) -> Bytes:
		let magic = bytes_from_ascii(text: "qoif")
		m_writer.extend(magic)

		m_writer.pack_u32_be(image.width)
		m_writer.pack_u32_be(image.height)
		m_writer.append(3)  # channels, 3 = RGB
		m_writer.append(0)  # colorspace

		# TODO: we can encode image more efficiently.
		# for now, store all pixels seperately
		let pixel = new_pixel()
		var y = 0
		while y < image.height:
			var x = 0
			while x < image.width:
				image.get_pixel(x, y, pixel)
				write_byte(0b11111110) # QOI_OP_RGB
				write_byte(pixel.red)
				write_byte(pixel.green)
				write_byte(pixel.blue)
				x += 1
			y += 1
		m_writer.to_bytes()

	fn write_byte(value?: int):
		m_writer.append(value)
