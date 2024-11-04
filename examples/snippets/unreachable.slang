
from std import print

fn main() -> int:
    let choice = Choice.Yes()
    let x = foo(choice)
    print("x = {x}")
    0

enum Choice:
    Yes
    No

fn foo(choice: Choice) -> int:
    case choice:
        Yes:
            return 1
        No:
            return 3
