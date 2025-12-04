
from std import print

pub fn main() -> int:
	let a = foo(a: 2, b: 5, message: "Fiir")
	let message = "No sir"
	let b = foo(a: 9, b: 5, message)
	many_args(a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10)
	0

enum Option[T]:
	Some(value: T)

enum Symbol:
	A
	B

fn foo(a: int, b: int, message: str) -> Option[Symbol]:
	if a < b:
		print("A smaller than B")
	else:
		print(message)

	Option.Some(Symbol.B())

fn many_args(a: int, b: int, c: int, d: int, e: int, f: int, g: int, h: int, i: int, j: int):
	""" Test a function with many arguments """
	print("a = {a}")
	print("b = {b}")
	print("c = {c}")
	print("d = {d}")
	print("e = {e}")
	print("f = {f}")
	print("g = {g}")
	print("h = {h}")
	print("i = {i}")
	print("j = {j}")
