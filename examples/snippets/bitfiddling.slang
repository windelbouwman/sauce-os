"""
Try various bit fiddle operations.
"""
from std import print

pub fn main() -> int:
	let a = 0x543
	let b = a >> 2
	let c = a << 4
	let d = a & b
	let e = a | c
	let f = c ^ e
	print("a={a}")
	print("b={b}")
	print("c={c}")
	print("d={d}")
	print("e={e}")
	print("f={f}")
	print("OK")
	0
