
# Idea: provide interfaces, which will be implemented as vtables


from std import print

fn main() -> int:
	let x = 2
	let y = 3
	if check_hash(v1: 2, v2: y):
		print("EQ")
	else:
		print("NOPE")

	if check_hash(v1: 'a', v2: 'b'):
		print("Nein")
	0

fn check_hash[T](v1: Hashable[T], v2: Hashable[T]) -> bool:
	let h1 = v1.hash()
	let h2 = v2.hash()

	if h1 == h2:
		# v1.equal(other: v2)
		true
	else:
		false

interface Hashable[T]:
	fn hash() -> int
	fn equal(other: T) -> bool

impl Hashable[int] for int:
	fn hash() -> int:
		this

	fn equal(other: int) -> bool:
		this == other
