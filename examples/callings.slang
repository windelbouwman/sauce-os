
import std

fn main() -> int:
    foo(2, 5, "Fiir")
    foo(9, 5, "No sir")
    return 0

fn foo(a: int, b: int, message: str):
    if a < b:
        std::print("A smaller than B")
    else:
        std::print(message)

