
from std import print, exit, get_time

pub fn panic(message?: str) -> unreachable:
	print("PANIC: {message}")
	exit(code: 1)

pub fn unimplemented(message?: str) -> unreachable:
	panic("UNIMPLEMENTED: {message}")

pub fn assert(condition: bool, message: str):
	if not condition:
		panic(message)
