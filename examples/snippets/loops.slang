

import std

fn main() -> int:
    let x = 0

    loop:
        x = x + 1
        std.print("1: x = {x}")

        if x > 5:
            break
        else:
            continue

    std.print("while")

    while x < 10:
        x = x + 1
        std.print("2: x = {x}")
        continue

    0
