module main
"""Try various bit fiddle operations."""

from std import print

pub fn main() -> int:
	let a = 0x543
	let b = a >> 2
	let c = a << 4
	let d = a & b
	let e = a | c
	let f = c ^ e
	print("{a=}")
	print("{b=}")
	print("{c=}")
	print("{d=}")
	print("{e=}")
	print("{f=}")
	print("OK")
	0
