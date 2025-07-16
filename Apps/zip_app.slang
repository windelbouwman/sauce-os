
import std
from utils import set_log_level, log_error, log_info
from gzip import gzip_compress
from qoi import write_bytes_to_file, read_whole_file_as_bytes

pub fn main() -> int:

	let n = std.get_n_args()
	var i = 0
	var input_filename: str = ""
	var output_filename: str = ""
	while i < n:
		let argument = std.get_arg(arg: i)
		if i == 0:
			input_filename = argument
		elif i == 1:
			output_filename = argument
		i += 1

	if std.str_len(text: input_filename) == 0:
		log_error("Needs input filename")
		return 1

	if std.str_len(text: output_filename) == 0:
		log_error("Needs output filename")
		return 1

	set_log_level(level: 5)
	log_info("Reading {input_filename}")
	let data = read_whole_file_as_bytes(filename: input_filename)
	let data2 = gzip_compress(data)
	log_info("Writing {output_filename}")
	write_bytes_to_file(filename: output_filename, data: data2)
	return 0
