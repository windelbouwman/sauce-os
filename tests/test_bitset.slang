
from std import print
from bitset import BitSet
from unittest import assert_int_equals, assert_true, assert_false

pub fn main() -> int:
	let s = BitSet()
	assert_int_equals(s.count(), 0)

	s.set(5)
	assert_int_equals(s.count(), 1)
	assert_false(s.isset(0))
	assert_false(s.isset(4))
	assert_true(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(7))

	s.set(7)
	assert_int_equals(s.count(), 2)
	assert_false(s.isset(4))
	assert_true(s.isset(5))
	assert_false(s.isset(6))
	assert_true(s.isset(7))
	assert_false(s.isset(8))

	s.clear(5)
	assert_int_equals(s.count(), 1)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_true(s.isset(7))
	assert_false(s.isset(8))

	s.clear(7)
	assert_int_equals(s.count(), 0)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(7))
	assert_false(s.isset(8))

	s.set(177)
	assert_int_equals(s.count(), 1)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(7))
	assert_false(s.isset(8))
	assert_true(s.isset(177))

	s.clear(177)
	assert_int_equals(s.count(), 0)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(7))
	assert_false(s.isset(8))
	assert_false(s.isset(177))

	print("OK")
	0
