
import std

fn add3(a: int, b: int) -> int:
    return a + b + 3


fn mul5(a: int) -> int:
    return a * (2 + 2 + 1)

struct NumberAndText:
    a: int
    b: str

fn display_both(value: NumberAndText):
    std.print("NumberAndText (a={value.a}, b={value.b})")

fn get_bar[T](foo: Foo[T]) -> T:
    # Get a t from bar foo
    case foo:
        Bar(t):
            return t

enum Foo[T]:
    Bar(t: T)

