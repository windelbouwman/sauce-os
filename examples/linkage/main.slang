
from std import print
from fancy import add3, mul5, display_both, NumberAndText

fn main() -> int:
    let r = mul5(a: add3(a: 1, b: 2))
    print("RES: {r}")

    let x = NumberAndText(b: "a", a: 42)
    display_both(x)
    return 0
