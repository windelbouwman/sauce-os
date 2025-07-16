
""" Calculate md5sum from given file.
"""

import std
from crypto import md5, sha256
from qoi import read_whole_file_as_bytes

pub fn main() -> int:
	let n = std.get_n_args()
	var i = 0
	var filename: str = ""
	while i < n:
		let argument = std.get_arg(arg: i)
		filename = argument
		i += 1

	if std.str_len(text: filename) == 0:
		return 1

	let text = std.read_file(filename)
	let data = read_whole_file_as_bytes(filename)
	std.print("{filename}:")
	std.print("MD5: {md5(data).as_hex()}")
	std.print("SHA2565: {sha256(data).as_hex()}")

	0
