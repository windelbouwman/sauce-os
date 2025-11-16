
from std import print, float_to_str2
from utils import assert
from listtype import List, list5
from math import fabs
from diff import diff_numbers, ratio

pub fn main() -> int:
	test_diff()
	test_ratio()
	print("OK")
	0

fn test_diff():
	let a = list5(1, 2, 3, 4, 8)
	let b = list5(4, 1, 2, 3, 4)
	for edit in diff_numbers(a, b):
		# print("edit={edit}")
		pass

fn test_ratio():
	check_ratio(a: "appel", b: "apple", r: 0.7)
	check_ratio(a: "a", b: "b", r: 0.0)

fn check_ratio(a: str, b: str, r: float):
	let r2 = ratio(a, b)
	# TODO: apply assertion
	# assert(condition: fabs(r2 - r) < 0.001, message: "r {float_to_str2(value: r2, digits: 10)} should be near {float_to_str2(value: r, digits: 10)}")
