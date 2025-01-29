# Spiffy example case where we need a so called bridge function to be introduced during type erasure.

from std import print

pub fn main() -> int:
	let strCombo = Combo:
		data: "Moi"
		handler: str_handler  # We need the bridge function here
	invoke(c: strCombo)

	strCombo.handler = str_handler  # We need the bridge function here again
	invoke(c: strCombo)

	0

fn invoke(c: Combo):
	c.handler(c.data, 42)

fn str_handler(data: str, value: int):
	print("data = {data}, value = {value}")

struct Combo[T]:
	data: T
	handler: fn(T, int)
