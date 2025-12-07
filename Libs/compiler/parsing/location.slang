
from std import str_get
from strlib import is_lf

pub struct Location2:
	begin: int
	end: int

# offset (22 bits) + size (10 bits) in a single integer
pub type Location = int

pub fn new_location(begin: int, end: int) -> Location:
	# Location(begin, end)
	let size = end - begin
	(begin << 10) | (size & 0x3FF)

pub fn location_default() -> Location:
	location_at(offset: 0)

pub fn get_begin(x?: Location) -> int:
	# x.begin
	x >> 10

pub fn get_end(x?: Location) -> int:
	# x.end
	let begin = x >> 10
	let size = x & 0x3FF
	begin + size

pub fn merge_locations(begin: Location, end: Location) -> Location:
	new_location(begin: get_begin(begin), end: get_end(end))

pub fn location_at(offset: int) -> Location:
	let begin = offset
	let end = offset
	new_location(begin, end)

pub struct Position:
	row: int
	column: int

pub fn offset_to_position(offset: int, code: str) -> Position:
	""" Calculate row and column from offset in string."""
	var index = 0
	var row = 1
	var column = 1
	while index < offset:
		let c = str_get(text: code, index)
		if is_lf(c):
			row += 1
			column = 1
		else:
			column += 1
		index += 1
	Position(row, column)
