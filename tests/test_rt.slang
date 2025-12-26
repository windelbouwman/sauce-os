
from std import print
from unittest import assert_int_equals
from rt import ctz, popcnt

pub fn main() -> int:
	assert_int_equals(ctz(12), 2)
	assert_int_equals(popcnt(0xE), 3)
	assert_int_equals(popcnt(8), 1)
	assert_int_equals(ctz(8), 3)
	print("OK")
	0
