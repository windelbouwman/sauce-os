

import std

enum Option:
    None
    Some(str)
    Money(int, float)

# class<x> List:
     # var element : x 

fn main():
    # let x: list<float> = [1,7,11,2]
    # let x: float = [1,7,11,2]
    let x = [1,7,11,2,550,232,12,2]

    std::print("x[2] = " + std::int_to_str(x[2]))
    std::print("x[1] = " + std::int_to_str(x[1]))

    for a in x:
        std::print("BOOM a=" +         std::int_to_str(a) + " a*a="+ std::int_to_str(a*a))

    # This works as well:
    # let opt = [Option::None, Option::Some("W00t!"), Option::None, Option::None]
