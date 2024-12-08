

import std

#enum Option:
#    None
#    Some(str)
#    Money(int, float)

# class<x> List:
     # var element : x 

struct Holder:
    a: int
    b: float

pub fn main() -> int:
    # let x: list<float> = [1,7,11,2]
    # let x: float = [1,7,11,2]
    let x = [1,7,11,2,550,232,12,2]
    # let x = [1, 7]

    std.print("x[2] = {x[2]}")
    std.print("x[1] = {x[1]}")

    # For loop with array:
    for a in x:
        std.print("BOOM a={a} a*a={a*a}")

    # While loop with array:
    let i = 2
    while i < 7:
        std.print("WHILE BOOM x[{i}]={x[i]}")
        i = i + 1

    # This works as well:
    # let opt = [Option.None, Option.Some("W00t!"), Option.None, Option.None]

    # TODO: use y
    # let y = [3.4, 2.2, 2.2]

    # Array of structs!
    let z1 = Holder:
        a: 2
        b: 3.2
    let z2 = Holder:
        a: 6
        b: 9.2
    let z = [z1, z2]
    std.print("z[1].a = {z[1].a}")

    for c in "hello":
        std.print(">{c}")

    0
