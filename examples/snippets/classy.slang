
from std import print

class Bar:
    var val1: int = 2
    var val2: float = 3.14
    var val3: str

    fn info(x: int):
        print("Bar instance {x + this.val1}")
        info2()

    fn info2():
        print("Bar instance: " + val3)


fn main() -> int:
    let bar = Bar(val3: "Woei!")
    bar.info(x: 2)

    let baz = Bar(val3: "Hello world")
    baz.info(x: 3)
    return 0
