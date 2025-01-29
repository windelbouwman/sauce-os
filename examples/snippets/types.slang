
# Example with some basic types
from std import print

pub fn main() -> int:
	let a: int = 1
	let b: float = 2.0
	let c: str = "drie"
	let d: uint8 = uint8(4)
	let e: uint16 = uint16(5)
	let f: uint32 = uint32(6)
	let g: uint64 = uint64(7)
	let h: int8 = int8(8)
	let i: int16 = int16(9)
	let j: int32 = int32(10)
	let k: int64 = int64(11)
	let l: float32 = float32(12.12)
	let m: float64 = 13.13
	let p: char = 'x'

	print("a = {a}")
	print("c = {c}")
	print("p = {p}")
	print("c[2] = {c[2]}")

	let ee = add16(a: uint16(7), b: e)
	# d = 255
	0

fn add16(a: uint16, b: uint16) -> uint16:
	a + b
