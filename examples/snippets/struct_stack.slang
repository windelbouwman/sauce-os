module main
"""Example of a struct which can be allocated on the stack"""

from std import print

pub fn main() -> int:
	let p = Pair(a: 3, b: 8)
	print("p.a={p.a}")
	0

struct Pair:
	a: int
	b: int
