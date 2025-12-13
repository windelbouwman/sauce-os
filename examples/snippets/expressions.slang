
from std import print

pub fn main() -> int:
	let x = 2
	let y: int = 6
	let z = (x + 2 - 9 * 10) / y
	print("x = {x}")
	print("z = {z}")
	if z + 5 < 10.0 - 2 or x <= 2 and y == x or x > 2 or y >= 100:
		print("BOOM")
	else:
		print("BAR")

	if "aa" == "bb":
		print("Woei1")
	else:
		if "cc" == "cc":
			print("Woei2")
		else:
			print("Woei3")

	let a = 41
	print("75% of {a} = {threequarters(x: a)}")

	print("Remainder 17 / 5 = {17 % 5}")
	# This should error:
	# 2 = 5
	0

fn threequarters(x: int) -> int:
	2 + (x * 3) / 4
