
from std import print, float_to_str2
from utils import assert
from math import modulo, fabs, floor, ceil, factorial, sin, cos, log10, exp, sqrt
from unittest import assert_int_equals

pub fn main() -> int:
	test_float_literals()
	test_modulo()
	test_factorial()
	test_floor_ceil()
	test_sqrt()
	test_sin()
	test_cos()
	test_log()
	test_exp()
	print("OK")
	0

fn test_float_literals():
	""" Test various notations of floating point numbers. """
	assert_are_close(1e3, 1000)
	assert_are_close(1e1, 10)
	assert_are_close(1e-3, 0.001)
	assert_are_close(1.00e+3, 1000)
	assert_are_close(1.000e+1, 10)
	assert_are_close(1.0000e-3, 0.001)
	assert_are_close(0.1e-4, 0.00001)

fn test_modulo():
	assert_int_equals(modulo(value: 9, divisor: 5), 4)
	assert_int_equals(modulo(value: 6, divisor: 5), 1)
	assert_int_equals(modulo(value: 10, divisor: 5), 0)
	assert_int_equals(modulo(value: 11, divisor: 2), 1)
	assert_int_equals(modulo(value: 8, divisor: 2), 0)

fn test_factorial():
	assert_int_equals(factorial(0), 1)
	assert_int_equals(factorial(1), 1)
	assert_int_equals(factorial(2), 2)
	assert_int_equals(factorial(3), 6)
	assert_int_equals(factorial(4), 24)
	assert_int_equals(factorial(5), 120)

fn test_sqrt():
	assert_are_close(sqrt(4), 2)
	assert_are_close(sqrt(9), 3)
	assert_are_close(sqrt(16), 4)
	assert_are_close(sqrt(25), 5)
	assert_are_close(sqrt(2), 1.414213562373095)

fn test_sin():
	let pi = 3.141592653589793
	check_sin(angle: 0, 0)
	check_sin(angle:0.5 * pi, 1)
	check_sin(angle: pi, 0)
	check_sin(angle: 1.5 * pi, -1)
	check_sin(angle: 2 * pi, 0)
	check_sin(angle: 2, 0.90929742682568)

fn check_sin(angle: float, value?: float):
	assert_are_close(sin(angle), value)

fn test_cos():
	let pi = 3.141592653589793
	check_cos(angle: 0, 1)
	check_cos(angle: 0.5 * pi, 0)
	check_cos(angle: pi, -1)
	check_cos(angle: 1.5 * pi, 0)
	check_cos(angle: 2 * pi, 1)

fn check_cos(angle: float, value?: float):
	assert_are_close(cos(angle), value)

fn test_log():
	check_log10(10, expected: 1)
	check_log10(100, expected: 2)
	check_log10(200, expected: 2.30102999566398)
	check_log10(1, expected: 0)
	check_log10(1000, expected: 3)

fn check_log10(value?: float, expected: float):
	assert_are_close(log10(value), expected)

fn test_exp():
	check_exp(0, expected: 1)
	check_exp(1, expected: 2.718281828459045)
	check_exp(3.14, expected: 23.1038668587221)
	# check_exp(10, expected: 22026.465794806718)
	check_exp(-4, expected: 0.01831563888873418)
	check_exp(-7, expected: 0.000911881965554516)

fn check_exp(value?: float, expected: float):
	assert_are_close(exp(value), expected)

fn test_floor_ceil():
	#assert_int_equals(2, floor(2.0))
	#assert_int_equals(2, ceil(2.0))

	assert_int_equals(5, floor(5.0001))
	assert_int_equals(6, ceil(5.0001))

	assert_int_equals(7, floor(7.999))
	assert_int_equals(8, ceil(7.999))

	assert_int_equals(-3, floor(-2.7))
	assert_int_equals(-2, ceil(-2.7))

	assert_int_equals(-6, floor(-5.01))
	assert_int_equals(-5, ceil(-5.01))

	#assert_int_equals(-2, floor(-2.0))
	#assert_int_equals(-2, ceil(-2.0))

fn assert_are_close(a?: float, b?: float):
	let diff = fabs(a - b)
	let rtol = 0.000000001
	let atol = 0.00000000000000001  # A small margin
	let average = fabs(a + b) / 2.0
	let tol = average * rtol + atol # relative tolerance
	assert(condition: diff < tol, message: "{float_to_str2(value: a, digits: 20)} is not close to {float_to_str2(value: b, digits: 20)} diff={float_to_str2(value: diff, digits: 20)} tol={float_to_str2(value: tol, digits: 20)}")
