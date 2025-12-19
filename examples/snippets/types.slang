
# Example with some basic types
from std import print

type Z = int

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
	var q: [uint8] = [uint8(4), uint8(8), uint8(199)]
	let z: Z = 10

	q[1] = uint8(42)

	print("a = {a}")
	print("c = {c}")
	print("d = {int(d)}")
	print("e = {int(e)}")
	print("h = {int(h)}")
	print("i = {int(i)}")
	print("k = {int(k)}")
	print("p = {p}")
	print("c[2] = {c[2]}")
	print("q[0] = {int(q[0])}")
	print("q[1] = {int(q[1])}")
	print("q[2] = {int(q[2])}")
	print("z = {z}")
	print("addZ = {addZ(a: 3)}")

	let ee = add16(a: uint16(7), b: e)
	print("ee = {int(ee)}")

	let ff = add8(a: uint8(15), b: d)
	print("ff = {int(ff)}")

	# d = 255
	0

fn add32(a: uint32, b: uint32) -> uint32:
	a + b

fn add16(a: uint16, b: uint16) -> uint16:
	a + b

fn add8(a: uint8, b: uint8) -> uint8:
	a + b

fn addZ(a: Z) -> Z:
	a + 2
