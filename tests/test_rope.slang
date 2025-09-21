""" Test rope data structure. """

from std import print
from rope import new_rope
from unittest import assert_str_equals


pub fn main() -> int:
	test_rope()
	print("OK")
	0


fn test_rope():
	let r = new_rope(text: "hllo")
	r.insert(pos: 1, text: "e")
	r.insert(pos: 5, text: "world")
	r.insert(pos: 5, text: " ")
	assert_str_equals(r.get_text(), "hello world")
	r.delete(pos: 4, size: 3)
	r.delete(pos: 5, size: 3)
	assert_str_equals(r.get_text(), "hello")
