module main
"""hexdump utility"""

from std import read_file, print, get_n_args, get_arg, chr
from base.bytes import byte_as_hex
from base.fs import Path, new_path
from base.listtype import List
from base.strlib import str_join, int_to_hex_string, str_pad_left

pub fn main() -> int:
	let options = parse_options()
	if options.show_help:
		print_usage()
		return 0

	for filename in options.filenames:
		let data = filename.read_bytes()
		var offset = 0
		while offset < data.len():
			let address = str_pad_left(text: int_to_hex_string(offset), length: 8, fill: "0")
			let byte_parts: List[str] = List()
			let ascii_parts: List[str] = List()
			var i = 0
			while i < 16 and offset < data.len():
				let b = data.get(index: offset)
				byte_parts.append(byte_as_hex(uint8(b)))
				ascii_parts.append(str(chr(b)) if b > 31 and b < 127 else ".")
				i += 1
				offset += 1
			let bytes_text = str_join(parts: byte_parts, sep: " ")
			let ascii_text = str_join(parts: ascii_parts, sep: "")
			print("{address}  {bytes_text}  |{ascii_text}|")
	0

struct Options:
	filenames: List[Path]
	show_help: bool

fn parse_options() -> Options:
	let options = Options:
		filenames: List()
		show_help: false

	var i = 0
	let n = get_n_args()
	while i < n:
		let argument = get_arg(arg: i)
		if argument == "-h" or argument == "--help":
			options.show_help = true
		else:
			options.filenames.append(new_path(filename: argument))
		i += 1
	options


fn print_usage():
	print("Usage:")
	print("$ hexdump <options> file")
	print("")
	print("   -h --help : show help")
