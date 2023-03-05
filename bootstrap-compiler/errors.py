from rich import print
from .location import Location


def print_error(code, location: Location, message: str):
    context_amount = 5
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

        if row_nr > location.row + context_amount:
            break


class CompilationError(RuntimeError):
    pass


class ParseError(CompilationError):
    pass


class LexError(CompilationError):
    pass
