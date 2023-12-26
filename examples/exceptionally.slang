
# Ideas about exceptions
from std import print

fn main():
    try:
        let y: int = foo(x: false)
        try:
            raise "Ai"
        except (ex2: str):
            print("Inner raise = {ex2}!")
        try:
            print("y1 = {y}")
        except (ex3: str):
            print("Inner raise 2 = {ex3}!")
        y = foo(x: true)
        print("y2 = {y}")
    except(err_val: str):
        print("ERROR: {err_val}")

fn foo(x: bool) -> int except str:
    let x1 = may_bork(do_bork: false)
    let x2 = may_bork(do_bork: x)
    return x1 + x2

fn may_bork(do_bork: bool) -> int except str:
    print("We might bork!")
    if do_bork:
        raise "Oh noes"
    else:
        return 42

