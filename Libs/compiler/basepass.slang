
# Unique number generator
import ast

pub class IdGen:
	var counter: int = 1
	pub var m_void_type: ast.Type = ast.void_type()

	pub fn new_id() -> int:
		let v = counter
		counter += 1
		v
