
from std import print
from integersetlib import new_int_set, integer_set_equals
from unittest import assert_true

pub fn main() -> int:
	print("OK")
	test_intersection()
	test_difference()
	0

fn test_intersection():
	let s1 = new_int_set(begin: 1, end: 10)
	let s2 = new_int_set(begin: 2, end: 4)
	let s3 = new_int_set(begin: 3, end: 6)
	let s4 = new_int_set(begin: 3, end: 4)
	let s5 = s1.union(other: s2)
	s5 = s5.union(other: s3)
	assert_true(integer_set_equals(a: s4, b: s5))

fn test_difference():
	let s1 = new_int_set(begin: 1, end: 10)
	let s2 = new_int_set(begin: 2, end: 4)
	let s3 = new_int_set(begin: 1, end: 2).union(other: new_int_set(begin: 4, end: 10))
	let s4 = s1.difference(other: s2)
