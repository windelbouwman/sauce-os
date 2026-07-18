module main
"""Calculate md5sum from given file."""

import std
from base.crypto import md5, sha256
from base.fs import new_path, Path
from base.listtype import List

pub fn main() -> int:
	let options = parse_options()
	if options.show_help:
		print_usage()
		return 0

	if options.filenames.is_empty():
		print_usage()
		return 1

	for path in options.filenames:
		let data = path.read_bytes()
		std.print("{path}:")
		std.print("MD5: {md5(data).as_hex()}")
		std.print("SHA2565: {sha256(data).as_hex()}")
	0

struct Options:
	filenames: List[Path]
	show_help: bool

fn parse_options() -> Options:
	let options = Options:
		filenames: List()
		show_help: false

	var i = 0
	let n = std.get_n_args()
	while i < n:
		let argument = std.get_arg(arg: i)
		if argument == "-h" or argument == "--help":
			options.show_help = true
		else:
			options.filenames.append(new_path(filename: argument))
		i += 1
	options

fn print_usage():
	std.print("Usage:")
	std.print("  md5sum <filename>")
