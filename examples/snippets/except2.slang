
from std import print

pub fn main() -> int:
	try:
		let v1 = ohnoes(x: 1)
		print("Yes: v1={v1}")
		let v2 = ohnoes(x: 2)
		print("Yes: v2={v2}")
		let v3 = ohnoes(x: 12)
		print("Yes: v3={v3}")
	except (ex: str):
		print("Error: {ex}")
	0

fn ohnoes(x: int) -> int except str:
	if x > 10:
		raise "No ({x})"
	else:
		2 + x
