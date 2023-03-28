import std

struct Holder:
    msg1: str
    msg2: str

struct Fu:
    a: int
    msg: str
    b: int

fn main() -> int:
    let messages = Holder:
        msg1: "Hello c22ool world!!"
        msg2: "W02220t"
    foo(messages)
    let k = Fu:
        a: 2
        msg: "BOOM1"
        b: 5
    bar(k, messages)
    let x = 31
    x = 10
    k.a = x
    bar(k, messages)
    let k3 = Fu:
        a: 10
        msg: "BOOM2"
        b: 55
    bar(k3, messages)
    return 0

fn foo(messages: Holder):
    std::print(messages.msg1)
    std::print(messages.msg2)

fn bar(kung: Fu, messages: Holder):
    if kung.a < kung.b:
        std::print(kung.msg)
    else:
        foo(messages)
