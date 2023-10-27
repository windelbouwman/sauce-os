
from std import print, int_to_str, read_file
from datatypes import List, vec1, Option
from strlib import split_lines, str_repeat, str_pad_right
from location import Location, location_to_string

struct CompilationError:
    filename: Option[str]
    errors: List[SingleCompilationError]

struct SingleCompilationError:
    location: Location
    message: str

fn new_error(location: Location, message: str) -> SingleCompilationError:
    return SingleCompilationError(location, message)

fn new_errors(filename: Option[str], errors: List[SingleCompilationError]) -> CompilationError:
    return CompilationError(filename, errors)

fn display_error(error: CompilationError):
    for error2 in error.errors:
        case error.filename:
            Some(filename):
                print_error(filename, location: error2.location, message: error2.message)
            None:
                print("ERROR: {location_to_string(error2.location)} -> {error2.message}")

fn print_error(filename: str, location: Location, message: str):
    print("      +---------------[ {filename} ]-----------------")
    let code = read_file(filename)
    let row = 1
    let target_row = location.begin.row
    let nr_context_rows = 4
    for line in split_lines(text: code):
        if target_row - nr_context_rows <= row and row <= target_row + nr_context_rows:
            let row_text = str_pad_right(text: int_to_str(row), length: 5, fill: " ")
            print(" {row_text}| {line}")
            let pre_text = "      |"

            if row == target_row:
                let indent = pre_text + str_repeat(text: " ", count: location.begin.column)
                let lexeme_width = 1
                if location.end.column > location.begin.column:
                    lexeme_width = location.end.column - location.begin.column + 1
                let pointer = str_repeat(text: "^", count: lexeme_width)
                let indent2 = indent + str_repeat(text: " ", count: lexeme_width / 2)
                print("{indent}{pointer}")
                print("{indent2}|")
                print("{indent2}|")
                print("{indent2}+-----< {message}")
                print("{pre_text}")

        row += 1
    print("      +----------------------------------------------")
    print("")
