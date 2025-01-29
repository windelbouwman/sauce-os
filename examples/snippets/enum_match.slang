
import std


enum Option:
	None
	Some(value: str)
	Money(amount: int)


pub fn main() -> int:
	let val: Option = Option.Some("TXT")
	foo(val: val)
	let val2: Option = Option.None()
	foo(val: val2)
	0


fn foo(val: Option):
	# TODO: implement match
	#match val:
	case val:
		None:
			std.print("Nothing here")
		Some(x):
			std.print(x)
	else:
		pass
