
import std

pub fn main() -> int:
	let msg = "Hello cool world!!"
	std.print(msg)
	# std.print(msg)
	foo()
	std.print("Cool escaping: hex-41:\x41 backslash:\\ double-quote:\"")
	std.print("Yes" if 1 > 1 else "No" if false else "maybe")
	0

fn foo():
	if 2 < 7 - 1:
		std.print("Hello world2")
