
from std import print

fn main():
    # Becomes: store  void()* @bla, void()** %x_1

    let x: fn() = bla
    let y = 2
    x()
    call_f(x)
    call_f(baz)
    x = baz
    call_f(bla)
    x()

    let z = A:
        func1: bla
        func2: baz

    complexor(z)

    return

struct A:
    func1: fn()
    func2: fn()

fn complexor(x: A):
    print("Complexor entry")
    call_f(x.func1)
    call_f(x.func2)
    print("Complexor exit")

fn bla():
    print("In bla!")
    return

fn baz():
    print("In baz!")
    return

fn call_f(x: fn()):
    print("pre-fn!")
    x()
    print("post-fn!")
