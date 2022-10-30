# slang-lang description

This document describes the slang-lang programming
language.

# Hello world

```
import std

fn main():
    std::print("Hello world")

```

# Functions

Function are defined using the `fn` keyword.
Type annotations are given after the function
parameters.

Example:

```
fn add_two(x: int) -> int:
    return x + 2

```

# If statement

If statements are implemented using the `if` and `else` keywords.

Example:

```
fn main():
    let x = 15
    if x < 10:
        std::print("x is a small number")
    else:
        std::print("x is somewhat larger")
```

# Loop statement

```
fn example():
    let x = 1
    while x < 10:
        x = x + 1
```

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
fields.

Example:

```

struct Animal:
    species: str
    weight: float

fn main():
    let tiger = Animal:
        species: "cat"
        weight: 143.2

```
