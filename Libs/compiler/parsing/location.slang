
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
