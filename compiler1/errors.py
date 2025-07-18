from rich import print
import rich.markup
from functools import lru_cache
from .location import Location


def count_leading_tabs(line: str) -> int:
    return len(line) - len(line.lstrip("\t"))


def print_error(code: str, filename: str, location: Location, message: str):
    print("***********************", filename, location)
    context_amount = 5
    was_printed = False
    for row_nr, text in enumerate(code.splitlines(), start=1):
        if row_nr < location.begin.row - context_amount:
            continue

        print(f"[italic]{row_nr:5}[/italic]:\t{rich.markup.escape(text)}")
        if row_nr == location.begin.row:
            tabs = count_leading_tabs(text)
            indent = (
                " " * 6 + "\t" + "\t" * tabs + " " * (location.begin.column - 1 - tabs)
            )
            lexeme_length = max(location.end.column - location.begin.column, 1)
            pointer = indent + "^" * lexeme_length
            indent += " " * (lexeme_length // 2)
            print(pointer)
            print(indent + "|")
            print(indent + f"+----< [bold]{message}[/bold]")
            was_printed = True

        if row_nr > location.begin.row + context_amount:
            break

    if not was_printed:
        print(f"{location}: {message}")


@lru_cache(maxsize=50)
def read_source(filename: str) -> str:
    with open(filename, "r") as f:
        return f.read()


def print_errors(errors):
    for filename, location, message in errors:
        code = read_source(filename)
        print_error(code, filename, location, message)


class CompilationError(RuntimeError):
    def __init__(self, errors):
        super().__init__()
        self.errors = errors


class ParseError(RuntimeError):
    def __init__(self, location: Location, message: str):
        super().__init__()
        self.location = location
        self.message = message
