
from std import print

pub fn main() -> int:
	try:
		raise new_ex()
		print("Yes")
	except (ex: Ex):
		print("Error: {ex.msg}")
	0

fn new_ex() -> Ex:
	Ex(msg: "No")

struct Ex:
	msg: str
