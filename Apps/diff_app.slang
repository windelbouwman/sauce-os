module main
"""Print differences between text files."""

from std import print, get_n_args, get_arg
from base.logging import set_log_level, log_info
from base.strlib import str_to_int
from base.listtype import List
from base.fs import Path, new_path
from base.diff import diff_lines, render_diff, count_diff_changes, show_unified

pub fn main() -> int:
	let arguments = parse_arguments()
	if arguments.show_help:
		print_usage()
		return 0

	if arguments.files.len() != 2:
		print("Diff requires 2 files to diff.")
		print_usage()
		return 2

	# set_log_level(level: 3)
	let f1 = arguments.files.get(index: 0)
	let f2 = arguments.files.get(index: 1)
	log_info("Comparing {f1} and {f2}")
	let a = f1.read_lines()
	let b = f2.read_lines()
	let edits = diff_lines(a, b)
	let n_diffs = count_diff_changes(edits)
	if n_diffs > 0:
		if arguments.show_unified:
			show_unified(edits, context: arguments.context_lines)
		else:
			render_diff(edits, show_unchanged_lines: false)
		1
	else:
		0

struct Arguments:
	show_help: bool
	show_unified: bool
	context_lines: int
	files: List[Path]

fn parse_arguments() -> Arguments:
	let arguments = Arguments:
		show_help: false
		show_unified: false
		context_lines: 0
		files: List()
	let n = get_n_args()
	var i = 0
	while i < n:
		let argument = get_arg(arg: i)
		i += 1
		if argument == "-h" or argument == "--help":
			arguments.show_help = true
		elif argument == "-u":
			arguments.show_unified = true
			arguments.context_lines = 3
		elif argument == "-U":
			arguments.show_unified = true
			if i < n:
				arguments.context_lines = str_to_int(get_arg(arg: i))
				i += 1
		else:
			arguments.files.append(new_path(filename: argument))
	arguments

fn print_usage():
	print("Usage:")
	print("CMD> diff_app.exe file1 file2")
