

struct Location:
    begin: Position
    end: Position

fn location_default() -> Location:
    return location_at(row: 1, column: 1)

fn location_to_string(location?: Location) -> str:
    return "{location.begin.row}:{location.begin.column}"

fn location_at(row: int, column: int) -> Location:
    let begin = Position(row, column)
    let end = Position(row, column)
    return Location(begin, end)

struct Position:
    row: int
    column: int

