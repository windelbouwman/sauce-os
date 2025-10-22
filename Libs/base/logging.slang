""" Logger.

"""

from std import print, get_time

var log_level: int = 0

pub fn set_log_level(level: int):
	log_level = level

pub fn log_error(message?: str):
	log_it(level: "ERROR", message)

pub fn log_warning(message?: str):
	log_it(level: "WARNING", message)

pub fn log_info(message?: str):
	if log_level > 0:
		log_it(level: "INFO", message)

pub fn log_debug(message?: str):
	if log_level > 1:
		log_it(level: "DEBUG", message)

pub fn log_trace(message?: str):
	if log_level > 2:
		log_it(level: "TRACE", message)

fn log_it(level: str, message: str):
	let t = get_time()
	print("{level} @ {t}: {message}")
	# print("{level}: {message}")
