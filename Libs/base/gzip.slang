
# See RFC-1952: GZIP file format.

from datetime import unix_to_str
from math import modulo
from utils import unimplemented, assert, log_debug
from bytes import Bytes, ByteArray, ByteReader
from deflate import new_deflate_decoder
from deflate import deflate_compress

fn read_zero_terminated_string(reader: ByteReader) -> str:
	let out = ByteArray()
	loop:
		let b = reader.read_byte()
		if b == 0:
			break
		else:
			out.append(b)
	return out.to_bytes().as_ascii()

pub fn gzip_decompress(data?: Bytes) -> Bytes:
	# Handle the gzip header.
	let reader = data.into_reader()
	let id1 = reader.read_byte()
	let id2 = reader.read_byte()
	assert(condition: id1 == 0x1f, message: "Expect ID1: 0x1F")
	assert(condition: id2 == 0x8B, message: "Expect ID1: 0x8B")
	let cm = reader.read_byte()
	assert(condition: cm == 8, message: "Expect only DEFLATE (8) as compression")
	let flg = reader.read_byte()
	let mtime = reader.read_u32_le()
	let xfl = reader.read_byte()
	let os = reader.read_byte()
	log_debug("OS = {os} mtime={unix_to_str(seconds: mtime)}")

	# bit 0   FTEXT
	# bit 1   FHCRC
	# bit 2   FEXTRA
	# bit 3   FNAME
	# bit 4   FCOMMENT

	if (flg >> 2) & 1 == 1:  # FEXTRA
		unimplemented("FEXTRA")

	if (flg >> 3) & 1 == 1:  # FNAME
		let fname = read_zero_terminated_string(reader)
		log_debug("FNAME: {fname}")

	if (flg >> 4) & 1 == 1:  # FCOMMENT
		let fcomment = read_zero_terminated_string(reader)
		log_debug("FCOMMENT: {fcomment}")

	if (flg >> 1) & 1 == 1:  # FHCRC
		unimplemented("FHCRC")

	# Invoke deflate here
	let decoder = new_deflate_decoder(reader)
	let decompressed = decoder.deflate()

	let crc32 = reader.read_u32_le()
	let isize = reader.read_u32_le()
	assert(condition: isize == decompressed.len(), message: "Invalid length: {isize} != {decompressed.len()}")
	let crc32_check = calc_crc32(data: decompressed)
	log_debug("isize = {isize}, crc32 = {crc32}, crc32_check = {crc32_check}")
	assert(condition: crc32_check == crc32, message: "CRC error: {crc32} != {crc32_check}")
	decompressed

pub fn gzip_compress(data: Bytes) -> Bytes:
	let out = ByteArray()

	# Header:
	out.append(0x1f)
	out.append(0x8b)
	let cm = 8  # compression method: deflate (8)
	let flg = 0
	let mtime = 0
	let xfl = 0
	let os = 255
	out.append(cm)
	out.append(flg)
	out.pack_u32_le(mtime)
	out.append(xfl)
	out.append(os)

	# Compressed data:
	let compressed_data = deflate_compress(data)
	out.extend(compressed_data)

	out.pack_u32_le(calc_crc32(data))
	out.pack_u32_le(data.len())

	out.to_bytes()

pub fn calc_crc32(data: Bytes) -> int:
	# Create table:
	var crc_table = [256 : int]
	var n = 0
	while n < 256:
		var c = n
		var k = 0
		while k < 8:
			if (c & 1) == 1:
				c = 0xedb88320 ^ (c >> 1)
			else:
				c = c >> 1
			k += 1
		crc_table[n] = c
		n += 1

	# Calculate CRC:
	var crc = 0
	crc = crc ^ 0xffffffff
	for b in data:
		crc = crc_table[(crc ^ b) & 0xff] ^ (crc >> 8)
	crc ^ 0xffffffff

pub fn zlib_decompress(data: Bytes) -> Bytes:
	# See RFC 1950
	let reader = data.into_reader()

	# header byte 1:
	let cmf_byte = reader.read_byte()
	let cm = cmf_byte & 0xF  # Compression method
	assert(condition: cm == 8, message: "Only support deflate in zlib format")
	let cinfo = (cmf_byte >> 4) & 0xF
	assert(condition: cinfo == 7, message: "Only support 32K window size")

	# header byte 2
	let flg_byte = reader.read_byte()

	# Check fcheck, CMF*256+FLG must be multiple of 31:
	assert(condition: modulo(value: cmf_byte * 256 + flg_byte, divisor: 31) == 0, message: "FCHECK failed")
	let fdict = (flg_byte >> 5) & 1
	if fdict == 1:
		unimplemented("FDICT unsupported")

	let decoder = new_deflate_decoder(reader)
	let decompressed = decoder.deflate()

	# ADLER32 checksum:
	let crc2 = calc_adler32(data: decompressed)
	let crc1 = reader.read_u32_be()
	assert(condition: crc1 == crc2, message: "CRC mismatch {crc1} != {crc2}")
	decompressed

pub fn zlib_compress(data: Bytes) -> Bytes:
	# Compress data in zlib format
	# See RFC 1950
	let out = ByteArray()

	# Write header:
	let cmf = 0x78
	out.append(cmf)
	let flg = 0x9c
	out.append(flg)

	# Compressed data:
	let compressed_data = deflate_compress(data)
	out.extend(compressed_data)

	# CRC of the uncompressed data:
	let crc = calc_adler32(data)
	out.pack_u32_be(crc)

	out.to_bytes()

pub fn calc_adler32(data: Bytes) -> int:
	var s1 = 1
	var s2 = 0
	var index = 0
	while index < data.len():
		s1 = modulo(value: s1 + data.get(index), divisor: 65521)
		s2 = modulo(value: s2 + s1, divisor: 65521)
		index += 1
	(s2 * 65536) + s1
