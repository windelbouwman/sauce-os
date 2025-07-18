
from std import float_to_str
from utils import panic

# TODO: make constant
pub var pi: float = 3.141592653589793
pub var e: float = 2.718281828459045

pub fn min(a: int, b: int) -> int:
	if a < b:
		a
	else:
		b

pub fn max(a?: int, b?: int) -> int:
	if a > b:
		a
	else:
		b

# TODO: do something clever with traits / interfaces / generics
pub fn fmin(a?: float, b?: float) -> float:
	if a < b:
		a
	else:
		b

pub fn fmax(a?: float, b?: float) -> float:
	if a > b:
		a
	else:
		b

pub fn abs(a?: int) -> int:
	if a < 0:
		-a
	else:
		a

pub fn fabs(a?: float) -> float:
	if a < 0:
		-a
	else:
		a

pub fn sqrt(x?: float) -> float:
	""" Take the square root """
	if x < 0:
		panic("Square root undefined for negative numbers like {float_to_str(x)}")

	let eps = 1e-16
	var i = 0
	let N = 20
	var r = x / 2.0
	while fabs(x - r*r) > eps and i < N:
		r = (r + x / r) / 2.0
		i += 1
	r

# fn inv_sqrt(x?: float) -> float:
# IDEA: use quake initial guess
# 	x

pub fn factorial(x?: int) -> int:
	if x < 0:
		panic("Factorial undefined for negative numbers like {x}")
	elif x == 0:
		1
	else:
		var r = x
		while x > 2:
			x -= 1
			r *= x
		r

pub fn sin(x?: float) -> float:
	if x < 0:
		# When negative, use symmetric
		-sin(-x)
	else:
		# Reduce to the range of 0..2pi
		let two_pi = pi * 2.0
		x = fmod(value: x, divisor: two_pi)

		# Select the right quarter
		if x < 0.5* pi:
			sin_kernel(x)
		elif x < pi:
			sin_kernel(pi - x)
		elif x < 1.5 * pi:
			-sin_kernel(x - pi)
		else:
			-sin_kernel(two_pi - x)

pub fn cos(value?: float) -> float:
	# Use sine wave, by shifting pi/2:
	sin(value + (0.5 * pi))

fn sin_kernel(x?: float) -> float:
	"""
	Implement sin on range -pi/4 .. pi/4 by using a taylor series

				 x^3   x^5   x^7
	sin(x) ~ x - --- + --- - --- + --- ....
				  3!    5!    7!
	"""
	var result = 0.0
	var factor = x

	var i = 2
	while i < 30:
		result = result + factor
		# Calculate the next factor, based on the previous factor:
		factor = factor * (-(x*x) / (i*(i+1)))
		i += 2
	result

pub fn tan(value?: float) -> float:
	# TODO: check division by 0
	sin(value) / cos(value)

pub fn degrees(radians: float) -> float:
	""" Convert radians to degrees """
	radians * (180.0 / pi)

pub fn radians(degrees: float) -> float:
	""" Convert degrees to radians """
	degrees * (pi / 180.0)

fn fmod(x?: float, divisor: float) -> float:
	# TODO: how about negative numbers?
	if x > divisor:
		x - int(x / divisor) * divisor
	else:
		x

pub fn hypot(x?: float, y: float) -> float:
	sqrt(x*x + y*y)

pub fn modulo(value: int, divisor: int) -> int:
	let x = value / divisor
	value - (divisor * x)

pub fn powf(x?: float, y?: float) -> float:
	""" Raise x to the power of y.

	Implemented as:
	x^y = e^(y*log(x))

	This follow from: x^y = exp(log(x))^y = exp(y * log(x))
	"""
	exp(y * log(x))

pub fn log10(x?: float) -> float:
	log(x) / log(10)

pub fn log2(x?: float) -> float:
	log(x) / log(2)

pub fn log(x?: float) -> float:
	""" Natural logarithm

	See: https://en.wikipedia.org/wiki/Natural_logarithm
	For implementation algorithm: https://ben.land/post/2021/02/24/power-without-math-lib/

	Use the series:
				  2       ?
	log(x) = Sum ----- * (---)^(2n+1)
				 2*n+1    ?
	"""

	let q = 3.0
	if x > 0:
		if x > q:
			# For larger x, use the trick:
			# log(x) = log(p*q^r) = log(p) + r * log(q)
			var r = 0
			while x > q:
				x /= q
				r += 1
			log(x) + r * log(q)
		else:
			# range 0 .. 1
			let ratio = (x - 1) / (x + 1)
			var F = ratio
			var y = 0.0
			var n = 1
			loop:
				let term = F / n
				y = y + term
				if fabs(term) < 1e-17:
					break
				F = F * ratio * ratio
				n += 2
			2 * y
	else:
		panic("log({float_to_str(x)}) is undefined")

pub fn exp(x?: float) -> float:
	""" Use Taylor series:

			  x^1   x^2   x^3
	e^x = 1 + --- + --- + --- + ...
			   1!    2!    3!

	"""

	if x < 0:
		# exp(-z) = 1/exp(z)
		1/exp(-x)
	elif x > 1:
		# Use the fact that:
		# e^x = (e^(x/3))^3
		let r = exp(x / 3.0)
		r * r * r
	else:
		var sum = 1.0
		var term = 1.0
		var n = 1
		loop:
			term = term * (x / float(n))
			sum = sum + term
			n += 1
			# print("n = {n}")
			if term < 1e-18:
				break
			if n > 100:
				break
		sum

pub fn floor(value?: float) -> float:
	let i = int(value)
	if float(i) == value:
		value
	elif value < 0:
		float(i - 1)
	else:
		float(int(value))

pub fn ceil(value?: float) -> float:
	let i = int(value)
	if float(i) == value:
		value
	elif value < 0:
		float(i)
	else:
		float(i + 1)
