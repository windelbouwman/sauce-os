# Example of classes with generic types.

import std

class<V> Bar:
    var val1: int = 2
    var val3: str = "bla"

    fn info(v: V) -> V:
        std::print("Instance: {this.val1} " + this.val3)
        return v


fn main():
    let bar: Bar[Integer] = Bar()
    bar.val3 = "Woei!"
    bar.val1 = 1337
    let x = bar.info(Integer())
    std::print("integer: {x.v}")

    let baz: Bar[String] = Bar()
    baz.val3 = "Hello world"
    let y = baz.info(String())
    std::print("String:" + y.v)

class Integer:
    var v: int = 0

class String:
    var v: str = "-"
