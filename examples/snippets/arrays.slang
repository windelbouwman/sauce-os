
from std import print
from rt import int_to_str

fn main() -> int:
    let x = [1, 2, 3, 4]  # Array with 4 items
    let y = [1 : 100]   # Array with 100 items with value 1
    # let z = []  # Empty array? Do we want to support this?
    print(int_to_str(x[1]))
    print(int_to_str(x[2]))
    x[2] = 9
    print(int_to_str(x[2]))

    print2(values: x)
    print2(values: y)
    return 0

fn print2(values: [int]):
    print("Value 1: {values[1]}")
    print("Value 2: {values[2]}")
