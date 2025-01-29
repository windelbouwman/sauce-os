
from signal import butter

pub fn main() -> int:
	let f2 = butter(n: 2)
	f2.dump()
	let f3 = butter(n: 3)
	f3.dump()
	let f4 = butter(n: 4)
	f4.dump()
	let f5 = butter(n: 5)
	f5.dump()
	0
