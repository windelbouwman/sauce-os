""" Try statements as expressions """

import std

fn main() -> int:
    std.print("Int: {test(x: 7)}")
    std.print("Str: {test2(x: 1)}")
    let token = Token.Id(name: "w00t")
    std.print("Token: {test3(token)}")
    0

enum Token:
    Comma
    Id(name: str)

fn test(x: int) -> int:
    if x > 10:
        if x < 4:
            99
        else:
            8
    else:
        4

fn test2(x: int) -> str:
    switch x:
        0:
            "a"
        1:
            "B"
    else:
        "?"

fn test3(token: Token) -> str:
    case token:
        Comma:
            panic()
        Id(name):
            "Id({name})"

fn ugh(token: Token) -> int:
    case token:
        Comma:
            panic()
        Id(name):
            4

fn panic() ?:
    std.print("Oh noes!")
    std.exit(code: 2)
