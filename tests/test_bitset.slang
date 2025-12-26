
from std import print
from bitset import BitSet, new_bitset
from unittest import assert_int_equals, assert_true, assert_false

pub fn main() -> int:
	test_set_and_clear()
	test_equal()
	test_andnot()
	test_and()
	test_or()
	print("OK")
	0

fn test_set_and_clear():
	let s: BitSet = new_bitset(n: 190)
	s.set(5)
	assert_false(s.isset(0))
	assert_false(s.isset(4))
	assert_true(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(41))

	s.set(42)
	assert_false(s.isset(4))
	assert_true(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(41))
	assert_true(s.isset(42))
	assert_false(s.isset(43))

	s.clear(5)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(41))
	assert_true(s.isset(42))
	assert_false(s.isset(43))

	s.clear(42)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(41))
	assert_false(s.isset(42))
	assert_false(s.isset(43))

	s.set(177)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(41))
	assert_false(s.isset(42))
	assert_false(s.isset(43))
	assert_false(s.isset(176))
	assert_true(s.isset(177))
	assert_false(s.isset(178))

	s.clear(177)
	assert_false(s.isset(4))
	assert_false(s.isset(5))
	assert_false(s.isset(6))
	assert_false(s.isset(7))
	assert_false(s.isset(8))
	assert_false(s.isset(176))
	assert_false(s.isset(177))
	assert_false(s.isset(178))

fn test_equal():
	let s1: BitSet = new_bitset(n: 190)
	let s2: BitSet = new_bitset(n: 190)

	assert_true(s2.equals(s1))
	s1.set(177)
	s2.set(177)
	assert_true(s2.equals(s1))
	s1.clear(177)
	assert_false(s2.equals(s1))
	s2.clear(177)
	assert_true(s2.equals(s1))

fn test_andnot():
	let s1: BitSet = new_bitset(n: 190)
	let s2: BitSet = new_bitset(n: 190)
	let s3: BitSet = new_bitset(n: 190)

	s1.set(5)
	s1.set(13)
	s1.set(173)
	s1.set(42)

	s2.set(13)
	s2.set(42)

	s3.set(5)
	s3.set(173)

	s1.andnot_assign(s2)
	assert_true(s1.equals(s3))

fn test_and():
	let s1: BitSet = new_bitset(n: 190)
	let s2: BitSet = new_bitset(n: 190)
	let s3: BitSet = new_bitset(n: 190)

	s1.set(5)
	s1.set(13)
	s1.set(173)
	s1.set(172)

	s2.set(13)
	s2.set(175)

	s3.set(13)

	s1.and_assign(s2)
	assert_true(s1.equals(s3))

fn test_or():
	let s1: BitSet = new_bitset(n: 190)
	let s2: BitSet = new_bitset(n: 190)
	let s3: BitSet = new_bitset(n: 190)

	s1.set(5)
	s1.set(13)
	s1.set(172)
	s1.set(173)

	s2.set(13)
	s2.set(175)

	s3.set(5)
	s3.set(13)
	s3.set(172)
	s3.set(173)
	s3.set(175)

	s1.or_assign(s2)
	assert_true(s1.equals(s3))
