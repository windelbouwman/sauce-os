# slang-lang description

This document describes the slang-lang programming
language.

# Hello world

The obligatory hello world program.

```
import std

pub fn main() -> int:
    std.print("Hello world")
    0

```

# Functions

Function are defined using the `fn` keyword.
Type annotations are given after the function
parameters.

```
fn add_two(x: int) -> int:
    return x + 2

```

# If statement

If statements are implemented using the `if` and `else` keywords.


```
fn example():
    let x = 15
    if x < 10:
        std.print("x is a small number")
    else:
        std.print("x is somewhat larger")
```

# Switch statement

You can switch on integer values.

```
fn example(x: int):
    switch x:
        1:
            print("One")
        7:
            print("Seven")
    else:
        print("Other value")

```

# Loop statement

Create a while loop like this:

```
fn example():
    let x = 1
    while x < 10:
        x = x + 1
```

Create an endless loop:

```
fn example():
    let x = 1
    loop:
        x = x + 2
        if x > 10:
            break
        else:
            continue
```

# Structs

You can define struct data types, which have one
or more fields to store a group of related data.
When creating a struct, make sure to fill all its
fields. You can use two types of syntax to initialize
a struct.

```

fn example():
    let tiger = Animal:
        name: "tijgertje"
        weight: 143.2

    let cow = Animal(name: "sjakie", weight: 613.8)

struct Animal:
    name: str
    weight: float

```

# Classes

Classes contain both variables and functions.

```

fn example():
    let bot = Robot()
    bot.move(amount: 42)

class Robot:
    var x: int = 0
    var y: int = 0
    var angle: int = 0

    fn move(amount: int):
        if angle == 0:
            x += amount
        else:
            y += amount

    fn rotate(amount: int):
        angle += amount

```

# Enums

Enums can be used to have a value with different values inside.
They behave like rust enums.

```
from std import print

enum Choice:
    Some(value: int)
    None
    Two(a: int, b: int)

fn example():
    let choice = Choice.Some(value: 7)
    print_choice(choice)
    print_choice(choice: Choice.Two(a: 1, b: 2))
    print_choice(choice: Choice.None())

fn print_choice(choice: Choice):
    case choice:
        Some(value):
            print("Some value: {value})
        None:
            print("Nope")
        Two(a, b):
            print("Two values: {a} and {b})
```

# Generics

Structs and classes can be declared to contain generic values,
so they can be used to contain different types.

```
struct Message[T]:
    id: str
    value: T

fn example():
    let msg_int: Message[int] = Message(id: "x", value: 1)
    let msg_str: Message[str] = Message(id: "y", value: "foo")
```

# Interfaces

TODO
