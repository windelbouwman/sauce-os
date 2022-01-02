
import std

fn main():
    foo(2, 5, "Fiir")
    foo(9, 5, "No sir")

fn foo(a: int, b: int, message: str):
    if a < b:
        std::print("A smaller than B")
    else:
        std::print(message)

