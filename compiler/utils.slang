
from std import print, exit

fn panic(message: str):
    print("PANIC: {message}")
    exit(1)

fn assert(condition: bool, message: str):
    if condition:
        pass
    else:
        panic(message)

fn log_error(message: str):
    print("ERROR: {message}")

fn log_info(message: str):
    print("INFO: {message}")

fn log_debug(message: str):
    let do_debug = false
    if do_debug:
        print("DEBUG: {message}")
    

fn log_trace(message: str):
    let do_trace = false
    if do_trace:
        print("TRACE: {message}")
