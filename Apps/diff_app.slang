"""Print differences between text files."""

from std import print, read_file, get_n_args, get_arg
from strlib import split_lines
from logging import set_log_level, log_info
from listtype import List
from fs import Path, new_path
from optiontype import Option, option_unwrap
from diff import diff_lines

pub fn main() -> int:
	let n = get_n_args()
	var i = 0
	var parse_state = 0
	var f1_opt: Option[Path] = Option.None()
	var f2_opt: Option[Path] = Option.None()
	while i < n:
		let argument = get_arg(arg: i)
		if argument == "-h":
			print_usage()
			return 0
		else:
			if parse_state == 0:
				f1_opt = Option.Some(new_path(filename: argument))
				parse_state = 1
			elif parse_state == 1:
				f2_opt = Option.Some(new_path(filename: argument))
				parse_state = 2
			else:
				print("Too many arguments")
				return 1
		i += 1
	if parse_state != 2:
		print("Invalid arguments.")
		print_usage()
		return 2

	set_log_level(level: 3)
	var n_diffs = 0
	let f1 = option_unwrap(f1_opt)
	let f2 = option_unwrap(f2_opt)
	log_info("Comparing {f1} and {f2}")
	let a = f1.read_lines()
	let b = f2.read_lines()
	for edit in diff_lines(a, b):
		case edit:
			Equal(pos1, pos2, value):
				print("{pos1}..{pos2}: == {value}")
			Delete(pos, value):
				print("{pos}..: -- {value}")
				n_diffs += 1
			Insert(pos1, pos2, value):
				print("{pos1}..{pos2}: ++ {value}")
				n_diffs += 1
	if n_diffs > 0:
		print("Files differ")
	else:
		print("Files are the same")
	0

fn print_usage():
	print("Usage:")
	print("CMD> diff_app.exe file1 file2")
