
from std import print, int_to_str
from datatypes import List
from location import Location

enum CompilationError:
    Single(error: SingleCompilationError)
    Multi(errors: List[CompilationError])

struct SingleCompilationError:
    location: Location
    message: str

fn new_error(location: Location, message: str) -> CompilationError:
    let error = SingleCompilationError(location, message)
    return CompilationError.Single(error)

fn new_errors(errors: List[CompilationError]) -> CompilationError:
    return CompilationError.Multi(errors)

fn display_error(error: CompilationError):
    case error:
        Single(error):
            display_single_error(error)
        Multi(errs):
            for error in errs:
                display_error(error)

fn display_single_error(error: SingleCompilationError):
    print("ERROR: {int_to_str(error.location.row)}:{int_to_str(error.location.column)}: {error.message}")
