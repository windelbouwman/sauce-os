

from std import print, float_to_str2
from signal import butter
from unittest import assert_int_equals
from listtype import list1, list3, list4, list5, List
from utils import assert
from math import fabs
# from strlib import

pub fn main() -> int:
	test_butter()
	print("OK")
	0


fn test_butter():
	let but2 = butter(n: 2)
	but2.dump()
	assert_are_all_close(but2.b, list1(1.0))
	assert_are_all_close(but2.a, list3(1.0, 1.4142, 1.0))

	let but3 = butter(n: 3)
	but3.dump()
	assert_are_all_close(but3.b, list1(1.0))
	assert_are_all_close(but3.a, list4(1.0, 2.0, 2.0, 1.0))

	let but4 = butter(n: 4)
	but4.dump()
	assert_are_all_close(but4.b, list1(1.0))
	assert_are_all_close(but4.a, list5(1.0, 2.6131, 3.4142, 2.6131, 1.0))


fn assert_are_all_close(a?: List[float], b?: List[float]):
	assert_int_equals(a.len(), b.len())
	let i = 0
	while i < a.len():
		assert_are_close(a[i], b[i])
		i += 1


fn assert_are_close(a?: float, b?: float):
	let diff = fabs(a - b)
	let rtol = 0.001
	let atol = 0.0001  # A small margin
	let average = fabs(a + b) / 2.0
	let tol = average * rtol + atol # relative tolerance
	assert(condition: diff < tol, message: "{float_to_str2(value: a, digits: 20)} is not close to {float_to_str2(value: b, digits: 20)} diff={float_to_str2(value: diff, digits: 20)} tol={float_to_str2(value: tol, digits: 20)}")
