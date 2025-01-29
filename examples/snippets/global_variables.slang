
from std import print

pub fn main() -> int:
	display()
	modify()
	display()
	0


var x : int = 3
var y : str = "bla bla"


fn modify():
	x = 42
	y = "yo!"

fn display():
	print("x={x}, y={y}")
