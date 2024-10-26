

struct Location:
    begin: Position
    end: Position

fn location_default() -> Location:
    location_at(row: 1, column: 1)

fn location_to_string(location?: Location) -> str:
    "{location.begin.row}:{location.begin.column}"

fn location_at(row: int, column: int) -> Location:
    let begin = Position(row, column)
    let end = Position(row, column)
    Location(begin, end)

struct Position:
    row: int
    column: int

