
import std

struct<T> Bla:
    message: str
    value: T

struct<A> Fuu:
    x: A
    bla: Bla<Bla <A> >
    # bla: Bla<Bla<A> >

fn main():
    
    let a = Bla<int>:
        message: "Hello cool world!!"
        value: 2

    let b = Bla<bool>:
        message: "W00t"
        value: true
    
    std::print(a.message)
    std::print(b.message)

    let double_bla = Bla<Bla <bool> >:
        message: "double-bla"
        value: b

    let fu_b = Fuu<bool>:
        x: false
        bla: double_bla
    
    std::print(fu_b.bla.value.message)

    let triple_b = Bla < Bla<Bla <bool> > >:
        message: "double-bla"
        value: double_bla


# fn foo(x: Bla):
#     pass


