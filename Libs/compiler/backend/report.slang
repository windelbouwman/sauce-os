""" Internal reporting.

Useful for debugging the compilation stages.
"""

import std

pub class Report:
	var m_file: int = 0
	var m_enabled: bool = false

	pub fn set_enabled(v?: bool):
		if m_enabled:
			std.file_close(handle: m_file)
		m_enabled = v
		if v:
			m_file = std.file_open(filename: "compile-report.txt", mode: "w")

	pub fn is_enabled() -> bool:
		m_enabled

	pub fn writeln(text?: str):
		if m_enabled:
			std.file_writeln(handle: m_file, line: text)
