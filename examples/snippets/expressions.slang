
import std

pub fn main() -> int:
    let x = 2
    let y: int = 6
    let z = (x + 2 - 9 * 10) / y
    std.print("x = {x}")
    if z + 5 < 10.0 - 2 or x <= 2 and y == x or x > 2 or y >= 100:
        std.print("BOOM")
    else:
        std.print("BAR")

    if "aa" == "bb":
        std.print("Woei1")
    else:
        if "cc" == "cc":
            std.print("Woei2")
        else:
            std.print("Woei3")

    # This should error:
    # 2 = 5
    0
