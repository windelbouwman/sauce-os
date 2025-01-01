# Example of classes with generic types.

import std

class Bar[V]:
    pub var val1: int = 2
    pub var val3: str = "bla"

    pub fn info(v: V) -> V:
        std.print("Instance: {this.val1} " + this.val3)
        v


pub fn main() -> int:
    let bar: Bar[Integer] = Bar()
    bar.val3 = "Woei!"
    bar.val1 = 1337
    let x = bar.info(v: Integer())
    std.print("integer: {x.v}")

    let baz: Bar[String] = Bar()
    baz.val3 = "Hello world"
    let y = baz.info(v: String())
    std.print("String:" + y.v)
    0

class Integer:
    pub var v: int = 0

class String:
    pub var v: str = "-"
