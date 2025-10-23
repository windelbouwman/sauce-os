
from std import print
from listtype import List, list2, list3, list5
from diff import diff_numbers

pub fn main() -> int:
	test_diff()
	print("OK")
	0

fn test_diff():
	let a = list5(1, 2, 3, 4, 8)
	let b = list5(4, 1, 2, 3, 4)
	for edit in diff_numbers(a, b):
		# print("edit={edit}")
		pass
