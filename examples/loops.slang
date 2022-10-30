

import std

fn main():
    let x = 0

    loop:
        x = x + 1
        std::print("x = " + std::int_to_str(x))

        if x > 5:
            break
        else:
            continue

    std::print("while")

    while x < 10:
        x = x + 1
        std::print("x = " + std::int_to_str(x))
        continue
