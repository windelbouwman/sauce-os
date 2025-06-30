
# Idea: provide interfaces, which will be implemented as vtables

from std import print

pub fn main() -> int:
	dprint(value: 2)
	dprint(value: "bla")
	0

fn dprint(value: Debug):
	let txt = value.repr(a: 5)
	value.dummy()
	print("dprint: {txt}")
	value.dummy()

#fn make_dbg() -> Debug:
#	pass

interface Debug:
	fn repr(a: int) -> str
	fn dummy()

impl Debug for int:
	fn repr(a: int) -> str:
		"Integer of value: {this * a}"

	fn dummy():
		print("Dummy")

impl Debug for str:
	fn repr(a: int) -> str:
		"Str of value: {this} ({a})"

	fn dummy():
		print("STR Dummy")
