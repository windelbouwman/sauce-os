"""Functionality to operate on files and folders.

TODO: merge with pathlib?
"""

from bytes import Bytes, ByteArray
import std
from strlib import string_compare, split_string, split_lines
from listtype import List
from sorting import sort_list
from utils import panic, assert

pub fn lexical_sort_paths(values?: List[Path]) -> List[Path]:
	sort_list(values, cmp: path_compare)

pub fn path_compare(a: Path, b: Path) -> bool:
	string_compare(a: a.filename, b: b.filename)

pub fn new_path(filename: str) -> Path:
	Path(filename)

pub class Path:
	pub var filename: str

	pub fn read_text() -> str:
		std.read_file(filename: this.filename)

	pub fn read_lines() -> List[str]:
		split_lines(text: read_text())

	pub fn write_lines(lines?: List[str]):
		"""Write text lines to this path"""
		let handle = std.file_open(filename, mode: "w")
		for line in lines:
			std.file_writeln(handle, line)
		std.file_close(handle)

	pub fn to_string() -> str:
		filename

	pub fn get_extension() -> str:
		split_string(text: filename, sep: '.').last()

pub fn read_whole_file_as_bytes(path: Path) -> Bytes:
	# Helper to read in a whole file into a bytes object in memory
	let handle = std.file_open(filename: path.filename, mode: "rb")
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

pub fn write_bytes_to_file(path: Path, data: Bytes):
	let handle = std.file_open(filename: path.filename, mode: "wb")
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
