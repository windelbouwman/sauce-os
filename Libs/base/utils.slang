
from std import print, exit

fn panic(message?: str) -> unreachable:
    print("PANIC: {message}")
    exit(code: 1)

fn unimplemented(message?: str) -> unreachable:
    panic("UNIMPLEMENTED: {message}")

fn assert(condition: bool, message: str):
    if condition:
        pass
    else:
        panic(message)

var log_level: int = 0

fn set_log_level(level: int):
    log_level = level

fn log_error(message?: str):
    print("ERROR: {message}")

fn log_warning(message?: str):
    print("WARNING: {message}")

fn log_info(message?: str):
    if log_level > 0:
        print("INFO: {message}")

fn log_debug(message?: str):
    if log_level > 1:
        print("DEBUG: {message}")

fn log_trace(message?: str):
    if log_level > 2:
        print("TRACE: {message}")
