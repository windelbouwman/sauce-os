""" Try statements as expressions """

import std

pub fn main() -> int:
	std.print("Int: {test(x: 7)}")
	std.print("Str: {test2(x: 1)}")
	let token = Token.Id(name: "w00t")
	std.print("Token: {test3(token)}")
	let a = switch 3:
		2:
			1
		3:
			15
	else:
		100
	std.print("a={a}")
	std.print("x.b={get_x().b}")
	0

enum Token:
	Comma
	Id(name: str)

fn test(x: int) -> int:
	if x > 10:
		if x < 4:
			99
		else:
			8
	else:
		4

fn test2(x: int) -> str:
	switch x:
		0:
			"a"
		1:
			"B"
	else:
		"?"

fn test3(token: Token) -> str:
	case token:
		Comma:
			panic()
		Id(name):
			"Id({name})"

pub fn ugh(token: Token) -> int:
	case token:
		Comma:
			panic()
		Id(name):
			4

fn panic() -> unreachable:
	std.print("Oh noes!")
	std.exit(code: 2)

struct X:
	a: int
	b: int

fn get_x() -> X:
	X:
		a: 1
		b: 2
