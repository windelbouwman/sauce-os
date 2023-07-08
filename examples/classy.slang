
import std

class Bar:
    var val1: int = 2
    var val2: float = 3.14
    var val3: str = "bla"

    fn info():
        std.print("Bar instance: " + this.val3)
        # std.print(self.val3 )

    fn info2(x: int):
        std.print("Bar instance {x + this.val1}")


fn main() -> int:
    let bar = Bar()
    bar.val3 = "Woei!"
    bar.info()

    let baz = Bar()
    baz.val3 = "Hello world"
    baz.info()
    return 0
