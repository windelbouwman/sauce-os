

struct Location:
    begin: int
    end: int

fn location_default() -> Location:
    location_at(offset: 0)

fn location_at(offset: int) -> Location:
    let begin = offset
    let end = offset
    Location(begin, end)

struct Position:
    row: int
    column: int

#fn location_to_string(location?: Location) -> str:
#    "{location.begin.row}:{location.begin.column}"
