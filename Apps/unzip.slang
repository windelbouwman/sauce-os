module main
"""Unzip app"""

import std
from std import print
from base.logging import set_log_level, log_error, log_info
# from zip import open_archive
from base.fs import read_whole_file_as_bytes, new_path
from base.gzip import gzip_decompress

pub fn main() -> int:
	log_info("Unzip!")

	set_log_level(level: 2)

	let n = std.get_n_args()
	if n < 1:
		log_error("Needs input filename")
		print_usage()
		return 1
	let zip_path = new_path(filename: std.get_arg(arg: n - 1))

	let data = read_whole_file_as_bytes(path: zip_path)
	let data2 = gzip_decompress(data)

	# let x = open_archive(filename)

	0

fn print_usage():
	print("Usage:")
	print("CMD> unzip archive.zip")
