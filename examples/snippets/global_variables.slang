
from std import print

pub fn main() -> int:
	display()
	modify()
	display()
	0

struct Z:
	a: float
	b: str
	c: int
	w: W

struct W:
	val: int
	f: fn()

var x : int = 3
var y : str = "bla bla"
var z : Z = Z:
	a: 1.1
	b: "Moi"
	c: 5
	w: W(val: 7, f: handler)


fn modify():
	x = 42
	y = "yo!"
	z.b = "w00t"

fn display():
	print("x={x}, y={y}, z.b={z.b}")
	z.w.f()

fn handler():
	print("Handle!")
