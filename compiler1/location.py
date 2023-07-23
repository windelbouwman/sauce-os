""" Position information about tokens.

Each token starts and ends somewhere.
"""


class Location:
    def __init__(self, begin: "Position", end: "Position"):
        assert isinstance(begin, Position)
        assert isinstance(end, Position)
        self.begin = begin
        self.end = end

    def __repr__(self):
        return f"LOC=({self.begin}, {self.end})"

    @classmethod
    def default(cls):
        return cls(Position.default(), Position.default())


class Position:
    def __init__(self, row: int, column: int):
        self.row = row
        self.column = column

    def __repr__(self):
        return f"POS=({self.row}, {self.column})"

    @classmethod
    def default(cls):
        return cls(1, 1)
