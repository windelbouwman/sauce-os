
import std

fn main() -> int:
    let x = [1, 2, 3, 4]
    std.print(std.int_to_str(x[1]))
    std.print(std.int_to_str(x[2]))
    x[2] = 9
    std.print(std.int_to_str(x[2]))
    return 0
