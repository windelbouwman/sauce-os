

import std

fn main() -> int:
    std.print("Hello world")
    if 2 < 5:
        std.print("Compiling some stuff!")
    else:
        std.print("Not doing muchos!")

    if 2 < 5:
        std.print("two is less than five")

    if 10 < 5:
        std.print("ten is less than five")
    elif 5.2 > 2.1:
        std.print("elif1")
    elif 91.2 < 20.1:
        std.print("elif2")
#    else:
#        std.print("fubar")

    return 0
