
from std import print
from listtype import List
from unittest import assert_int_equals, assert_str_equals
from strlib import lexical_sort

pub fn main() -> int:
	test_sort_string_list()
	print("OK")
	0

fn test_sort_string_list():
	let x: List[str] = List()
	assert_int_equals(0, x.len())
	x.append("xa")
	x.append("gf")
	x.append("xf")
	x.append("ze")
	x.append("jb")
	let y = lexical_sort(x)
	assert_str_equals(y[0], "gf")
	assert_str_equals(y[1], "jb")
	assert_str_equals(y[2], "xa")
	assert_str_equals(y[3], "xf")
	assert_str_equals(y[4], "ze")
