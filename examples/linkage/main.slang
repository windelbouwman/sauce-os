
from std import print, float_to_str2
from fancy import add3, mul5
from fancy import display_both, NumberAndText
from fancy import Foo, get_bar

fn main() -> int:
    let r = mul5(a: add3(a: 1, b: 2))
    let r2 = float_to_str2(value: 3.14, digits: 5)
    print("RES: {r} {r2}")

    let x = NumberAndText(b: "a", a: 42)
    display_both(value: x)

    let foo = Foo.Bar(5)
    let t = get_bar(foo)
    print("t={t}")

    return 0

