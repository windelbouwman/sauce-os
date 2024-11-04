
import std

fn main() -> int:
    let a = foo(a: 2, b: 5, message: "Fiir")
    let message = "No sir"
    let b = foo(a: 9, b: 5, message)
    0

enum Option[T]:
    Some(value: T)

enum Symbol:
    A
    B

fn foo(a: int, b: int, message: str) -> Option[Symbol]:
    if a < b:
        std.print("A smaller than B")
    else:
        std.print(message)
    
    Option.Some(Symbol.B())

