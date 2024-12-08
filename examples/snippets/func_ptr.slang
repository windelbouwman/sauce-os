
from std import print

pub fn main() -> int:
    # Becomes: store  void()* @bla, void()** %x_1

    let x: fn() = bla
    # let y = 2
    x()
    call_f(x)
    call_f(x: baz)
    x = baz
    call_f(x: bla)
    x()

    let z = A:
        func1: bla
        func2: baz

    complexor(x: z)
    0

struct A:
    func1: fn()
    func2: fn()

fn complexor(x: A):
    print("Complexor entry")
    call_f(x: x.func1)
    call_f(x: x.func2)
    print("Complexor exit")

fn bla():
    print("In bla!")

fn baz():
    print("In baz!")

fn call_f(x: fn()):
    print("pre-fn!")
    x()
    print("post-fn!")
