
from std import print, exit

pub fn panic(message?: str) -> unreachable:
	print("PANIC: {message}")
	exit(code: 1)

pub fn unimplemented(message?: str) -> unreachable:
	panic("UNIMPLEMENTED: {message}")

pub fn assert(condition: bool, message: str):
	if not condition:
		panic(message)

var log_level: int = 0

pub fn set_log_level(level: int):
	log_level = level

pub fn log_error(message?: str):
	print("ERROR: {message}")

pub fn log_warning(message?: str):
	print("WARNING: {message}")

pub fn log_info(message?: str):
	if log_level > 0:
		print("INFO: {message}")

pub fn log_debug(message?: str):
	if log_level > 1:
		print("DEBUG: {message}")

pub fn log_trace(message?: str):
	if log_level > 2:
		print("TRACE: {message}")
