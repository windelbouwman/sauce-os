
from std import print, int_to_str
from location import Location

struct CompilationError:
    location: Location
    message: str

fn new_error(loc: Location, message: str) -> CompilationError:
    let e = CompilationError:
        location: loc
        message: message
    return e

fn display_error(error: CompilationError):
    print("ERROR: {int_to_str(error.location.row)}:{int_to_str(error.location.column)}: {error.message}")
