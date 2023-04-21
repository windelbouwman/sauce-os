
from std import print, int_to_str
from location import Location

struct CompilationError:
    location: Location
    message: str

# Ugh, TODO: conflicts with new_error in parsing.slang (due to names being used globally....)
fn new_error2(loc: Location, message: str) -> CompilationError:
    let e = CompilationError:
        location: loc
        message: message
    return e

fn display_error(error: CompilationError):
    print("ERROR: {int_to_str(error.location.row)}:{int_to_str(error.location.column)}: {error.message}")
