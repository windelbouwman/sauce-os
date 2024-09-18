
from std import print

fn main() -> int:
    let x = [1, 2, 3, 4]  # Array with 4 items
    let y = [100 : int]   # Array with 100 integers
    y[0] = 1
    y[1] = 1
    y[2] = 1
    # let z = []  # Empty array? Do we want to support this?
    print(str(x[1]))
    print(str(x[2]))
    x[2] = 9
    print(str(x[2]))

    print2(values: x)
    print2(values: y)
    return 0

fn print2(values: [int]):
    print("Value 1: {values[1]}")
    print("Value 2: {values[2]}")
