
import std

struct<T> Bla:
    message: str
    value: T

struct<A> Fuu:
    x: A
    bla: Bla<A>

fn main():
    
    let a = Bla<int>:
        message: "Hello cool world!!"
        value: 2

    let b = Bla<bool>:
        message: "W00t"
        value: true
    
    std::print(a.message)
    std::print(b.message)

    let fu_b = Fuu<bool>:
        x: false
        bla: b

# fn foo(x: Bla):
#     pass


