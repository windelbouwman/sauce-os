
# Idea: provide interfaces, which will be implemented as vtables


from std import print

fn main() -> int:
    let x = 2
    let y = 3
    if check_hash(2, y):
        print("EQ")
    else:
        print("NOPE")
    0

fn check_hash[T: Hashable](v1: T, v2: T) -> bool:
    let h1 = Hashable.hash(one: v1)
    let h2 = Hashable.hash(one: v2)
    if h1 == h2:
        return Hashable.equal(one: v1, other: v2)
    else:
        return false

interface Hashable:
    fn hash(one: T) -> int
    fn equal(one: T, other: T) -> bool

impl Hashable[int]:
    fn hash(one: int) -> int:
        return one

    fn equal(one: int, other: int) -> bool:
        return one == other
