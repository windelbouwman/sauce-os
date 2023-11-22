
from std import print

fn main():
    let choice = Choice.Yes()
    let x = foo(choice)
    print("x = {x}")

enum Choice:
    Yes
    No

fn foo(choice: Choice) -> int:
    case choice:
        Yes:
            return 1
        No:
            return 3
