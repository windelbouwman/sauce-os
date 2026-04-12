module main

from std import print
from base.random import Rand, new_rand
from base.unittest import assert_int_equals

pub fn main() -> int:
	test_rand_int()
	print("OK")
	0

fn test_rand_int():
	let r = new_rand()
	r.seed(initstate: uint64(42), initseq: uint64(54))

	let v1 = int(r.next())
	print("v1")
	assert_int_equals(v1, 2707161783)  # 0xa15c02b7

	let v2 = int(r.next())
	print("v2")
	assert_int_equals(v2, 2068313097)  # 0x7b47f409

	let v3 = int(r.next())
	print("v3")
	assert_int_equals(v3, 0xba1d3330)  # 3122475824

	let v4 = int(r.next())
	print("v4")
	assert_int_equals(v4, 0x83d2f293)  # 2211639955

	let v5 = int(r.next())
	print("v5")
	assert_int_equals(v5, 0xbfa4784b)  # 3215226955

	let v6 = int(r.next())
	print("v6")
	assert_int_equals(v6, 0xcbed606e)
