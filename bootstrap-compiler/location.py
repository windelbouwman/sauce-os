
class Location:
    def __init__(self, row: int, column: int):
        self.row = row
        self.column = column

    def __repr__(self):
        return f'LOC=({self.row}, {self.column})'
