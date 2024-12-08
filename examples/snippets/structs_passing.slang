from std import print

struct Holder:
    msg1: str
    msg2: str

struct Fu:
    a: int
    msg: str
    b: int

pub fn main() -> int:
    # let messages = new Holder:
    let messages = Holder:
        msg1: "Hello c22ool world!!"
        msg2: "W02220t"
    foo(messages)
    let k = Fu:
        a: 2
        msg: "BOOM1"
        b: 5
    bar(kung: k, messages)
    let x = 31
    x = 10
    k.a = x
    bar(kung: k, messages)
    let kung = Fu:
        a: 10
        msg: "BOOM2"
        b: 55
    bar(kung, messages)
    # delete messages
    0

# fn foo(messages: &Holder):
fn foo(messages: Holder):
    print(messages.msg1)
    print(messages.msg2)

fn bar(kung: Fu, messages: Holder):
# fn bar(kung: Fu, messages: &Holder):
    if kung.a < kung.b:
        print(kung.msg)
    else:
        foo(messages)
