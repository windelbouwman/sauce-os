

pub struct Location:
	begin: int
	end: int

pub fn location_default() -> Location:
	location_at(offset: 0)

pub fn location_at(offset: int) -> Location:
	let begin = offset
	let end = offset
	Location(begin, end)

pub struct Position:
	row: int
	column: int
