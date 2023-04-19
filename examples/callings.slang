
import std

fn main() -> int:
    let a = foo(2, 5, "Fiir")
    let b = foo(9, 5, "No sir")
    return 0

enum Option[T]:
    Some(T)

enum Symbol:
    A
    B

fn foo(a: int, b: int, message: str) -> Option[Symbol]:
    if a < b:
        std::print("A smaller than B")
    else:
        std::print(message)
    
    return Option.Some(Symbol.B())

