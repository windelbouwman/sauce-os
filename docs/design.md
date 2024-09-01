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

# Transformations

Compilation is done by transforming high level language features into lower level equivalents.
This has the benefit that we do not need to implement all language features during later code generation.

There are several transformations made in sequence:

- For loops to while loops
- 


# For loops

Each `for` loop is compiled into a `while` loop.

## Over array types

## Over sequence objects

If an object supports `len` and `get`, we use those methods.

```
for element in x:
    process_element(element)
```

Into this:

```
let size = x.len()
let index = 0
while index < size:
    let element = x.get(index)
    process_element(element)
```

## Over iterables

Non array types are looped over by invoking the `iter` method to retrieve an iterator.

```
for element in x:
    process_element(element)
```

Into this:

```
let it = x.iter()
loop:
    let opt = it.next()
    case opt:
        None:
            break
        Some(element):
            process_element(element)
```

# Enums

In general, enums are translated to tagged unions.

## General case
Compile to tagged unions.

```
enum Option[S, T]:
    None
    Some(value: S)
    Money(a: int, b: T)

fn demo():
    let option: Option[int, float] = Option.Money(a: 1, b: 3.14)
    case option:
        None:
            pass
        Some(value):
            pass
        Money(a, b):
            pass

```

Is translated into:

```
struct Option[S1, T1]:
    tag: int
    data: OptionData[S1, T1]

union OptionData[S2, T2]:
    data_Some: S2
    data_Money: OptionDataMoney[S2, T2]

struct OptionDataMoney[S3, T3]:
    a: int
    b: T3

fn demo():
    let option: Option[int, float] = Option:
        tag: 2
        data: OptionData[int, float](data2: OptionDataMoney[int, float](a: 1, b: 3.14)))
    let x = option
    switch x.tag:
        0:
            pass
        1:
            let value = x.data.data_Some:
            pass
        2:
            let a = x.data.data_Money.a
            let b = x.data.data_Money.b
            pass
    else:
        unreachable

```

## Special case 1: only tags

If the enum type contains only named tags, we can use only the tag as implementation.

```
enum Option:
    None
    Some
    Money

fn demo():
    let option = Option.Money()
    case option:
        None:
            pass
        Some:
            pass
        Money:
            pass

```

Is translated into:

```

fn demo():
    let option = 2
    let x = option
    switch x:
        0:
            pass
        1:
            pass
        2:
            pass
    else:
        unreachable

```

## Special case 2: two tags, and only one tag has data

If the enum has only two tags, and one of them contains data, we use a pointer
with a null-check.

```
enum Option[T]:
    None
    Some(T)

fn demo():
    let option1: Option[str] = Option.Some("w00t")
    let option2: Option[str] = Option.None()
    handle_option(option: option1)
    handle_option(option: option2)

fn handle_option(option: Option[str]):
    case option:
        None:
            handle_none()
        Some(value):
            handle_some(value)

fn handle_none():
    pass

fn handle_some(value: str):
    pass
```

Translates to:

```

fn demo():
    let option1: ptr = box("w00t")
    let option2: ptr = null
    handle_option(option: option1)
    handle_option(option: option2)

fn handle_option(option: ptr):
    let x = option
    if x == null:
        handle_none()
    else:
        let value = unbox(x, str)
        handle_some(value)

fn handle_none():
    pass

fn handle_some(value: str):
    pass

```

# Exceptions

We use checked exceptions. This means, you can only raise exceptions within an error handler. This prevents uncaught exceptions.

# Classes

Classes are lowered into structs and functions.

```
class Bar:
    var m_value: int

    fn add():
        m_value = m_value + 2
```

Translates to:

```
struct Bar:
    m_value: int

fn Bar_add(this: Bar):
    this.m_value = this.m_value + 2
```

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
