
from std import print, read_file, str_get
from datatypes import List, Option
from strlib import split_lines, str_repeat, str_pad_right, is_lf
from location import Location, Position

pub struct CompilationError:
    filename: Option[str]
    errors: List[SingleCompilationError]

pub struct SingleCompilationError:
    location: Location
    message: str

pub fn new_error(location: Location, message: str) -> SingleCompilationError:
    SingleCompilationError(location, message)

pub fn new_errors(filename: Option[str], errors: List[SingleCompilationError]) -> CompilationError:
    CompilationError(filename, errors)

pub fn display_error(error: CompilationError):
    for error2 in error.errors:
        render_message(label: "ERROR", filename: error.filename, location: error2.location, message: error2.message)

pub fn render_message(label: str, filename: Option[str], location: Location, message: str):
    case filename:
        Some(filename):
            print_error(filename, location, message)
        None:
            print("{label}: {message}")

fn offset_to_position(offset: int, code: str) -> Position:
    """ Calculate row and column from offset in string."""
    let index = 0
    let col_start = 0
    let row = 1
    while index < offset:
        let c = str_get(text: code, index)
        if is_lf(c):
            row += 1
            col_start = index + 1
        index += 1
    let column = offset - col_start + 1
    Position(row, column)

fn print_error(filename: str, location: Location, message: str):
    print("      +---------------[ {filename} ]-----------------")
    let code = read_file(filename)
    let begin = offset_to_position(offset: location.begin, code)
    let end = offset_to_position(offset: location.end, code)
    let target_row = begin.row
    let nr_context_rows = 4
    let row = 1
    for line in split_lines(text: code):
        if target_row - nr_context_rows <= row and row <= target_row + nr_context_rows:
            let row_text = str_pad_right(text: "{row}", length: 5, fill: " ")
            print(" {row_text}| {line}")
            let pre_text = "      |"

            if row == target_row:
                let indent = pre_text + str_repeat(text: " ", count: begin.column)
                let lexeme_width = 1
                if end.column > begin.column:
                    lexeme_width = end.column - begin.column + 1
                let pointer = str_repeat(text: "^", count: lexeme_width)
                let indent2 = indent + str_repeat(text: " ", count: lexeme_width / 2)
                print("{indent}{pointer}")
                print("{indent2}|")
                print("{indent2}+-----< {message}")
                print("{pre_text}")

        row += 1
    print("      +----------------------------------------------")
    print("")

# fn print_error_line(line: str, location: Location, message: str):
#     print(" {line}")
#     let indent = str_repeat(text: " ", count: location.begin.column)
#     let lexeme_width = 1
#     if location.end.column > location.begin.column:
#         lexeme_width = location.end.column - location.begin.column + 1
#     let pointer = str_repeat(text: "^", count: lexeme_width)
#     let indent2 = indent + str_repeat(text: " ", count: lexeme_width / 2)
#     print("{indent}{pointer}")
#     print("{indent2}|")
#     print("{indent2}+-----< {message}")
