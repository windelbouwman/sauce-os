
from std import print

pub fn main() -> int:
	if yes() or no():
		print("yes or no")
	if yes() and no():
		print("yes and no")
	if yes() and yes():
		print("yes and yes")
	if no() or no():
		print("no or no")
	0

fn yes() -> bool:
	print("YES")
	true

fn no() -> bool:
	print("NO")
	false
