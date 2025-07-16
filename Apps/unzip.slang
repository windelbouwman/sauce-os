"""
Unzip app
"""

import std
from std import print
from utils import set_log_level, log_error
# from zip import open_archive
from qoi import read_whole_file_as_bytes
from gzip import gzip_decompress

pub fn main() -> int:
	print("Unzip!")

	set_log_level(level: 2)

	let n = std.get_n_args()
	var i = 0
	var input_filename: str = ""
	while i < n:
		let argument = std.get_arg(arg: i)
		if i == 0:
			input_filename = argument
		i += 1

	if std.str_len(text: input_filename) == 0:
		log_error("Needs input filename")
		return 1

	let data = read_whole_file_as_bytes(filename: input_filename)
	let data2 = gzip_decompress(data)

	# let x = open_archive(filename)

	0
