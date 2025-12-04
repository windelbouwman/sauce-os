"""
Test various boolean operations
"""
from std import print

pub fn main() -> int:
	let yes = true
	let no = not yes
	let maybe = not yes or no and yes or not no
	print("OK" if yes else "YES")
	print("OK" if no else "YES")
	print("OK" if maybe else "YES")
	0
