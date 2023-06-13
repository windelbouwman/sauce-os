
from std import print, int_to_str
from datatypes import List
from location import Location

enum CompilationError:
    Single(SingleCompilationError)
    Multi(List[CompilationError])

struct SingleCompilationError:
    location: Location
    message: str

fn new_error(loc: Location, message: str) -> CompilationError:
    let e = SingleCompilationError:
        location: loc
        message: message
    return CompilationError.Single(e)

fn new_errors(errors: List[CompilationError]) -> CompilationError:
    return CompilationError.Multi(errors)

fn display_error(error: CompilationError):
    case error:
        Single(e):
            display_single_error(e)
        Multi(errs):
            for e in errs:
                display_error(e)

fn display_single_error(error: SingleCompilationError):
    print("ERROR: {int_to_str(error.location.row)}:{int_to_str(error.location.column)}: {error.message}")
