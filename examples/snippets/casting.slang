module main

from std import print

pub fn main() -> int:
	let v_i8 = int8(-4)
	let v_i16 = int16(-5)
	let v_i32 = int32(-6)
	let v_i64 = int64(-7)
	let v_f32: float32 = float32(-8.0)
	let v_f64: float64 = -9.0

	print("to i8")
	print_i8(int8(v_i8))
	print_i8(int8(v_i16))
	print_i8(int8(v_i32))
	print_i8(int8(v_i64))
	# print_i8(int8(v_f32))
	# print_i8(int8(v_f64))

	print("to i16")
	# print_i16(int16(v_i8))
	print_i16(int16(v_i16))
	print_i16(int16(v_i32))
	print_i16(int16(v_i64))
	# print_i16(int16(v_f32))
	# print_i16(int16(v_f64))

	print("to i32")
	print_i32(int32(v_i8))
	print_i32(int32(v_i16))
	print_i32(int32(v_i32))
	print_i32(int32(v_i64))
	print_i32(int32(v_f32))
	print_i32(int32(v_f64))

	print("to i64")
	print_i64(int64(v_i8))
	print_i64(int64(v_i16))
	print_i64(int64(v_i32))
	print_i64(int64(v_i64))
	print_i64(int64(v_f32))
	print_i64(int64(v_f64))

	print("to f32")
	# print_f32(float32(v_i8))
	# print_f32(float32(v_i16))
	print_f32(float32(v_i32))
	print_f32(float32(v_i64))
	# print_f32(float32(v_f32))
	print_f32(float32(v_f64))

	print("to f64")
	# print_f64(float64(v_i8))
	# print_f64(float64(v_i16))
	print_f64(float64(v_i32))
	print_f64(float64(v_i64))
	print_f64(float64(v_f32))
	# print_f64(float64(v_f64))

	0

fn print_i8(value?: int8):
	print("i8: {int(value)}")

fn print_i16(value?: int16):
	print("i16: {int(value)}")

fn print_i32(value?: int32):
	print("i32: {int(value)}")

fn print_i64(value?: int64):
	print("i64: {int(value)}")

fn print_f32(value?: float32):
	let value2 = int(value * float32(100))
	print("f32 * 100: {value2}")

fn print_f64(value?: float64):
	let value2 = int(value * float64(100))
	print("f64 * 100: {value2}")
