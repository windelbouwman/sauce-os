

from std import print
from settype import new_str_set
from unittest import assert_true, assert_false


pub fn main() -> int:
	test_set()
	print("OK")
	0


fn test_set():
	let x = new_str_set()
	assert_true(x.is_empty())
	x.add("one")
	x.add("two")
	x.add("two")
	assert_false(x.is_empty())
	assert_true(x.contains("one"))
	assert_false(x.contains("three"))
	x.remove("two")
	assert_false(x.is_empty())
	assert_false(x.contains("two"))
	x.remove("one")
	assert_true(x.is_empty())
	x.remove("one")
