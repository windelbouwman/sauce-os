
import std


enum Option:
    None
    Some(str)
    Money(int)


fn main():
    let val: Option = Option::Some("TXT")
    foo(val)
    let val2: Option = Option::None()
    foo(val2)


fn foo(val: Option):
    # TODO: implement match
    #match val:
    case val:
        None:
            std::print("Nothing here")
        Some(x):
            std::print(x)
    else:
        pass
