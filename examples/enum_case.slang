
import std


enum Option:
    None
    Some(str)
    Money(int, float)


fn main():
    #let val: Option = Option::Some("TXT")
    #foo(val)
    #let val2: Option = Option::None
    #foo(val2)
    let val3: Option = Option::Money(5, 2.3)


fn foo(val: Option):
    case val:
        # Option::None:
        #     std::print("Nothing here")
        Option::Some(x):
            std::print(x)
        Option::None:
            std::print("Nothing here")
        Option::Money(x,y):
            std::print("Money!!")
