module main
"""Calculate md5sum from given file."""

import std
from base.crypto import md5, sha256
from base.fs import read_whole_file_as_bytes, new_path

pub fn main() -> int:
	let n = std.get_n_args()
	if n < 1:
		print_usage()
		return 1

	let path = new_path(filename: std.get_arg(arg: n - 1))
	let data = read_whole_file_as_bytes(path)
	std.print("{path}:")
	std.print("MD5: {md5(data).as_hex()}")
	std.print("SHA2565: {sha256(data).as_hex()}")
	0

fn print_usage():
	std.print("Usage:")
	std.print("  md5sum <filename>")
