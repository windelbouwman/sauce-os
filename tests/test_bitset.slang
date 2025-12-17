
from std import print
from bitset import BitSet, new_bitset
from unittest import assert_int_equals, assert_true, assert_false

pub fn main() -> int:
	let s: BitSet = new_bitset(n: 190)

	s.set(5)
	assert_false(s.isset(0))
	assert_false(s.isset(4))
	assert_true(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(7))

	s.set(7)
	assert_false(s.isset(4))
	assert_true(s.isset(5))
	assert_false(s.isset(6))
	assert_true(s.isset(7))
	assert_false(s.isset(8))

	s.clear(5)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_true(s.isset(7))
	assert_false(s.isset(8))

	s.clear(7)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(7))
	assert_false(s.isset(8))

	s.set(177)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(7))
	assert_false(s.isset(8))
	assert_true(s.isset(177))

	s.clear(177)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(7))
	assert_false(s.isset(8))
	assert_false(s.isset(177))

	print("OK")
	0
