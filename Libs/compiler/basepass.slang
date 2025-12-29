
# Unique number generator

pub class IdGen:
	var counter: int = 1

	pub fn new_id() -> int:
		let v = counter
		counter += 1
		v
