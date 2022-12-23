
import std

struct<T> Bla:
    message: str
    value: T

struct<A> Fuu:
    x: A
    bla: Bla[Bla[A]]


fn main():
    
    let a = Bla[int]:
        message: "Hello cool world!!"
        value: 2

    let b = Bla[bool]:
        message: "W00t"
        value: true
    
    std::print(a.message)
    std::print(b.message)

    let double_bla = Bla[Bla[bool]]:
        message: "double-bla"
        value: b

    let fu_b = Fuu[bool]:
        x: false
        bla: double_bla
    
    display_fuu(fu_b)
    
    let triple_b = Bla[Bla[Bla[bool]]]:
        message: "triple-bla"
        value: double_bla
    
    std::print(triple_b.message)
    std::print(triple_b.value.message)
    std::print(triple_b.value.value.message)


fn display_fuu(fu_b: Fuu[bool]):
    std::print(fu_b.bla.message)
    std::print(fu_b.bla.value.message)


