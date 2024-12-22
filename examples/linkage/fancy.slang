
import std
from fubar import Foo
import fubar

var glbl: int = 3

pub fn add3(a: int, b: int) -> int:
    a + b + 3


pub fn mul5(a: int) -> int:
    a * (2 + 2 + 1)

pub struct NumberAndText:
    a: int
    b: str

pub fn display_both(value: NumberAndText):
    std.print("NumberAndText (a={value.a}, b={value.b})")

fn new_bar[T](f: T) -> fubar.Foo[T]:
    Foo.Bar(f)

pub fn get_bar[T](foo: Foo[T]) -> T:
    # Get a t from bar foo
    case foo:
        Bar(t):
            t


pub class Device[T]:
    var m_counter: int = 0
    var m_data: T

    fn exe() -> T:
        glbl += 4
        m_counter += 1
        std.print("Device exe: {m_counter}")
        m_data
