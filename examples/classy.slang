
import std

class Bar:
    var val1: int = 2
    var val2: float = 3.14
    var val3: str = "bla"

    fn info():
        std::print("Bar instance")
        std::print(val3 )
        # std::print(self.val3 )


fn main():
    std::print("Hello cool world!")
    let bar = Bar()
    bar.info()

    let baz = Bar()
    baz.info()

