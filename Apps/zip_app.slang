module main

import std
from base.logging import set_log_level, log_error, log_info
from base.optiontype import Option, option_unwrap, option_is_none
from base.gzip import gzip_compress
from base.fs import write_bytes_to_file, read_whole_file_as_bytes, Path, new_path

pub fn main() -> int:

	let n = std.get_n_args()
	var i = 0
	var input_path: Option[Path] = Option.None()
	var output_path: Option[Path] = Option.None()
	while i < n:
		let argument = std.get_arg(arg: i)
		if i == 0:
			input_path = Option.Some(new_path(filename: argument))
		elif i == 1:
			output_path = Option.Some(new_path(filename: argument))
		i += 1

	set_log_level(level: 5)

	if option_is_none(input_path):
		log_error("Needs input filename")
		return 1

	if option_is_none(output_path):
		log_error("Needs output filename")
		return 1

	log_info("Reading {option_unwrap(input_path)}")
	let data = read_whole_file_as_bytes(path: option_unwrap(input_path))
	let data2 = gzip_compress(data)
	log_info("Writing {option_unwrap(output_path)}")
	write_bytes_to_file(path: option_unwrap(output_path), data: data2)
	return 0
