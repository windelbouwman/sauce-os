
# Example with some basic types
from std import print, float_to_str2

type Z = int

pub fn main() -> int:
	let a: int = 1
	let b: float = 2.0
	let c: str = "drie"
	let d: uint8 = uint8(204)
	let e: uint16 = uint16(65001)
	let f: uint32 = uint32(6)
	let g: uint64 = uint64(7)
	let h: int8 = int8(8)
	let h2: int8 = int8(-8)
	let i: int16 = int16(9)
	let i2: int16 = int16(-9)
	let j: int32 = int32(10)
	let j2: int32 = int32(-10)
	let k: int64 = int64(11)
	let k2: int64 = int64(-11)
	let L: float32 = float32(12.12)
	let L2: float32 = float32(-12.12)
	let m: float64 = 13.13
	let m2: float64 = -13.13
	let p: char = 'x'
	var q: [uint8] = [uint8(4), uint8(8), uint8(199)]
	let z: Z = 10

	q[1] = uint8(42)

	print("a = {a}")
	print("c = {c}")
	print("d = {int(d)}")
	print("e = {int(e)}")
	print("h = {int(h)}")
	print("h2 = {int(h2)}")
	print("i = {int(i)}")
	print("i2 = {int(i2)}")
	# print("j = {int(j)}")
	# print("j2 = {int(j2)}")
	print("k = {int(k)}")
	print("k2 = {int(k2)}")
	print("L = {float_to_str2(value: float64(L), digits: 4)}")
	print("L2 = {float_to_str2(value: float64(L2), digits: 4)}")
	print("int(L) = {int(L)}")
	print("int(L2) = {int(L2)}")
	print("m = {float_to_str2(value: m, digits: 9)}")
	print("m2 = {float_to_str2(value: m2, digits: 9)}")
	print("int(m) = {int(m)}")
	print("int(m2) = {int(m2)}")
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
