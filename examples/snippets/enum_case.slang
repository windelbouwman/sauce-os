
from std import print
import std

enum Option:
    None
    Some(txt: str)
    Money(a: int, b: float)


pub fn main() -> int:
    let val: Option = Option.Some(txt: "TXT")
    foo(val)
    let val2 = Option.None()
    foo(val: val2)
    let val3: Option = Option.Money(a: 5, b: 2.3)
    foo(val: val3)
    0


fn foo(val: Option):
    case val:
        Some(x):
            print("And the message is: " + x)
        None:
            print("Nothing here")
        Money(x,y):
            print("Money!! x={x} y=" + std.float_to_str(y))
