import std

struct Holder:
    msg1: str
    msg2: str

fn main():
    let messages = Holder { msg1: "Hello c22ool world!!", msg2: "W02220t"  }
    foo(messages)

fn foo(messages: Holder):
    std.print(messages.msg1)
    std.print(messages.msg2)

