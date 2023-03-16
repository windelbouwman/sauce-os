from rich import print
from functools import lru_cache
from .location import Location


def print_error(code, location: Location, message: str):
    print('***********************')
    context_amount = 5
    was_printed = False
    for row_nr, text in enumerate(code.splitlines(), start=1):
        if row_nr < location.row - context_amount:
            continue

        print(f'[italic]{row_nr:05}[/italic]: {text}')
        if row_nr == location.row:
            indent = ' ' * (location.column + 6)
            pointer = indent + '^'
            print(pointer)
            print(indent + '|')
            print(indent + f'+----< [bold]{message}[/bold]')
            was_printed = True

        if row_nr > location.row + context_amount:
            break

    if not was_printed:
        print(f"{location}: {message}")


@lru_cache(maxsize=50)
def read_source(filename: str) -> str:
    with open(filename, 'r') as f:
        return f.read()


def print_errors(errors):
    for filename, location, message in errors:
        code = read_source(filename)
        print_error(code, location, message)


class CompilationError(RuntimeError):
    def __init__(self, errors):
        super().__init__()
        self.errors = errors


class ParseError(CompilationError):
    pass


class LexError(CompilationError):
    pass
