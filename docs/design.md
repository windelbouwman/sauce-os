# Functions

```
fn add(v1: int, v2: int) -> int:
    return v1 + v2
```

# Generic functions

Functions can have generic typed parameters:

```
fn vec2[T](v1: T, v2: T) -> List[T]:
    let result: List[T] = List()
    result.append(v1)
    result.append(v2)
    return result
```

# Arrays

Create fixed or dynamic arrays?

```
fn new_array(size: int) -> [int]:
    let result: [int] = [0, size]
    result[5] = 4
    return result
```

# Classes

Classes are lowered into structs and functions.

# Interfaces

Interfaces are implemented as vtables.

```

fn main() -> int:
    let y = 3
    if check_hash(2, y):
        print("EQ")
    return 0

fn check_hash[T: Hashable](v1: T, v2: T) -> bool:
    let h1 = Hashable.hash(one: v1)
    let h2 = Hashable.hash(one: v2)
    if h1 == h2:
        return Hashable.equal(one: v1, other: v2)
    else:
        return false

interface Hashable[T]:
    fn hash(T) -> int
    fn equal(T, T) -> bool

impl Hashable[int]:
    fn hash(one: int) -> int:
        return one

    fn equal(one: int, other: int) -> bool:
        return one == other

```

Will be compiled into:

```

fn main() -> int:
    let y = 3
    if check_hash(2, y):
        print("EQ")
    return 0

fn check_hash[T](vtable: Hashable[T], v1: T, v2: T) -> bool:
    let h1 = vtable.hash(one: v1)
    let h2 = vtable.hash(one: v2)
    if h1 == h2:
        return vtable.equal(one: v1, other: v2)
    else:
        return false

struct Hashable[T]:
    hash: fn(T) -> int
    equal: fn(T, T) -> bool

let vtable_int: Hashable[int] = Hashable:
    hash: Hashable_int_hash
    equal: Hashable_int_equal

fn Hashable_int_hash(one: int) -> int:
    return one

fn Hashable_int_equal(one: int, other: int) -> bool:
    return one == other

```

# Tips for compiler writers

- Use more passes. Do not do everything in one pass.
- Highlight syntax (strings, comments, keywords is enough)
- bootstrap using a VM or python

# Notes about LLVM backed implementation

See also:

https://mapping-high-level-constructs-to-llvm-ir.readthedocs.io/en/latest/basic-constructs/structures.html

# Implementation notes

Manual lexing:

https://craftinginterpreters.com/scanning.html

precedence climbing:

https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing
