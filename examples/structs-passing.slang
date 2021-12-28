import std

struct Holder:
    msg1: str
    msg2: str

struct Fu:
    a: int
    msg: str
    b: int

fn main():
    let messages = Holder { msg1: "Hello c22ool world!!", msg2: "W02220t"  }
    foo(messages)
    let k = Fu { a: 2, msg: "BOOM1", b: 5 }
    bar(k, messages)
    let x = 31
    x = 10
    k.a = x
    # let k3 = Fu { a: 10, msg: "BOOM2", b: 5 }
    bar(k, messages)

fn foo(messages: Holder):
    std.print(messages.msg1)
    std.print(messages.msg2)

fn bar(kung: Fu, messages: Holder):
    if kung.a < kung.b:
        std.print(kung.msg)
    else:
        foo(messages)
