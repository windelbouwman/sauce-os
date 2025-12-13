
from std import print

pub fn main() -> int:
	let p = Parser()
	let v = p.parse()
	print("Parsed: {v}")
	0

class Parser:
	var m_x: int = 5

	pub fn parse() -> int:
		try:
			do_add(parse_name())
		except (oei: str):
			print("Oei: {oei}")
		m_x

	fn parse_name() -> int except str:
		56

	fn do_add(value?: int):
		m_x = value
