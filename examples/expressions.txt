
import std

fn main():
    let x = 2
    let y = 6
    let z = (x + 2 - 9 * 10) / y
    std.print("x = {x}")
    if z + 5 < 10 - 2 or x <= 2 and y == z or x > 2 or y >= 100:
        std.print("BOOM")
    else:
        std.print("BAR")

