
from std import print

pub fn main() -> int:
	try:
		raise "No"
		print("Yes")
	except (ex: str):
		print("Error: {ex}")
	0
