module main
"""Handling of tar.gz files"""

import std
from base.fs import read_whole_file_as_bytes, new_path
from base.gzip import gzip_decompress
from base.datetime import unix_to_str
from base.bytes import ByteReader, bytes_to_ascii
from base.strlib import str_pad_left

pub fn main() -> int:
	let n = std.get_n_args()
	if n < 1:
		std.print("Usage:")
		std.print("UNTAR <archive.tar>")
		return 1
	let tar_filepath = new_path(filename: std.get_arg(arg: n - 1))
	std.print("UNTAR {tar_filepath} ...")

	let data = read_whole_file_as_bytes(path: tar_filepath)
	std.print("Read {data.len()} bytes..")

	let decompressed = gzip_decompress(data)
	std.print("Inflated to {decompressed.len()} bytes...")

	let reader = ByteReader(m_bytes: decompressed)
	untar(reader)
	0

fn roundup(reader: ByteReader):
	let value = reader.tell()
	let multiple = 512
	let remainder = value % multiple
	if remainder > 0:
		let size = multiple - remainder
		let padding = reader.read_bytes(size)

fn untar(reader: ByteReader):
	while not reader.at_end():
		let header = read_entry(reader)
		print_entry(header)
		if header.size > 0:
			let data = reader.read_bytes(size: header.size)
			roundup(reader)

struct Entry:
	path: str
	mode: int
	user_id: int
	group_id: int
	size: int
	timestamp: int
	user_name: str
	group_name: str

fn read_entry(reader: ByteReader) -> Entry:
	"""Read header"""
	let path = read_string(reader, size: 100)
	let mode = read_octal(reader, size: 8)
	let user_id = read_octal(reader, size: 8)
	let group_id = read_octal(reader, size: 8)
	let size = read_octal(reader, size: 12)
	let timestamp = read_octal(reader, size: 12)
	let checksum = read_octal(reader, size: 8)
	let file_type = reader.read_byte()
	let name = read_string(reader, size: 100)

	let ustar = reader.read_bytes(size: 6)
	let ustar_version = reader.read_bytes(size: 2)
	let user_name = read_string(reader, size: 32)
	let group_name = read_string(reader, size: 32)
	let device_major = reader.read_bytes(size: 8)
	let device_minor = reader.read_bytes(size: 8)
	let filename_prefix = read_string(reader, size: 155)

	roundup(reader)

	# std.print("USTAR: {bytes_to_ascii(data: ustar)}")

	Entry:
		path
		mode
		user_id
		group_id
		size
		timestamp
		user_name
		group_name

fn print_entry(header: Entry):
	let size_left_padded = str_pad_left(text: str(header.size), length: 10, fill: " ")
	std.print("{mode_to_str(mode: header.mode)} {header.user_name}/{header.group_name} {header.user_id}/{header.group_id} {size_left_padded} {unix_to_str(seconds: header.timestamp)} {header.path}")

fn s(m?: int) -> str:
	let r = "r" if m & 4 == 4 else "-"
	let w = "w" if m & 2 == 2 else "-"
	let x = "x" if m & 1 == 1 else "-"
	"{r}{w}{x}"

fn mode_to_str(mode: int) -> str:
	"-" + s(mode >> 6) + s(mode >> 3) + s(mode)

fn read_octal(reader: ByteReader, size: int) -> int:
	var value = 0
	var i = 0
	while i < size:
		let b = reader.read_byte()
		if b == 0 or b == 32:
			pass
		else:
			let digit = b - 48
			value = value * 8 + digit
		i += 1
	value

fn read_string(reader: ByteReader, size: int) -> str:
	let data = reader.read_bytes(size)
	bytes_to_ascii(data)
