
import std


enum Option:
    None
    Some(str)
    Money(int)


fn main():
    let val: Option = Option::Some("TXT")
    foo(val)
    let val2: Option = Option::None
    foo(val2)


fn foo(val: Option):
    match val:
        Option::None:
            std::print("Nothing here")
        Option::Some(x):
            std::print(x)
