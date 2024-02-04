
from std import print
from regex import compile, find_all

fn main() -> int:
    print("lexer generator")

    let prog = compile(pattern: "a+[0-9]")

    let numbers = find_all(pattern: "[0-9]+", text: "bla bla 1337 oei ai 42 wow 0")
    for number in numbers:
        print("Found match: {number}")

    let touching = find_all(pattern: "[a-z]+[0-9]+", text: "bla1337wow5a3w00t")
    for t in touching:
        print("Found match: {t}")

    return 0

