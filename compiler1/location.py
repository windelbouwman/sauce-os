"""Position information about tokens.

Each token starts and ends somewhere.
"""

import bisect


class Location:
    def __init__(self, begin: int, end: int):
        assert isinstance(begin, int)
        assert isinstance(end, int)
        self.begin = begin
        self.end = end

    def __repr__(self):
        return f"LOC=({self.begin}, {self.end})"

    @classmethod
    def default(cls):
        return cls(1, 1)


Span = Location


class Position:
    __slots__ = ("row", "column")

    def __init__(self, row: int, column: int):
        self.row = row
        self.column = column

    def __repr__(self):
        return f"POS=({self.row}, {self.column})"

    @classmethod
    def default(cls):
        return cls(1, 1)


class RowColumnCalculator:
    def __init__(self, text: str):
        self.text = text
        self.line_starts = [0]
        for i, ch in enumerate(text):
            if ch == "\n":
                self.line_starts.append(i + 1)

    def offset_to_row_column(self, offset: int):
        if offset < 0 or offset > len(self.text):
            raise ValueError(f"offset {offset} out of range")

        row = bisect.bisect_right(self.line_starts, offset) - 1
        column = offset - self.line_starts[row]
        return row, column

    def row_column_to_offset(self, position: Position) -> int:
        return self.line_starts[position.row] + position.column
