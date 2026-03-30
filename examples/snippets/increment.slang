module main

from std import print

var g: int = 2

pub fn main() -> int:
	let s = S(x: 2, field: 9)
	var y = 3
	y -= 9
	get_s(s, p: 11).field += 2
	print("y={y}")
	print("g={g}")
	print("field={s.field}")
	0

fn get_s(s: S, p: int) -> S:
	g += 1
	p += 1
	print("p={p}")
	s.field += 9
	s

struct S:
	x: int
	field: int
