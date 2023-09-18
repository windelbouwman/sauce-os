
import std

struct Bla[T]:
    message: str
    value: T

struct Fuu[A]:
    x: A
    bla: Bla[Bla[A]]

# Boxed version of a bool
struct Bool:
    value: bool

# Boxed integer
struct Int:
    value: int

fn main():
    
    let i_boxed = Int(value: 2)

    let a = Bla[Int]:
        message: "Hello cool world!!"
        value: i_boxed

    let b_boxed = Bool(value: true)

    let b = Bla[Bool]:
        message: "W00t"
        value: b_boxed
    
    std.print(a.message)
    std.print(b.message)

    let double_bla = Bla[Bla[Bool]]:
        message: "double-bla"
        value: b

    let b_false_boxed = Bool(value: false)

    let fu_b = Fuu[Bool]:
        x: b_false_boxed
        bla: double_bla
    
    display_fuu(fu_b)
    
    let triple_b = Bla[Bla[Bla[Bool]]]:
        message: "triple-bla"
        value: double_bla
    
    std.print(triple_b.message)
    std.print(triple_b.value.message)
    std.print(triple_b.value.value.message)


fn display_fuu(fu_b: Fuu[Bool]):
    std.print(fu_b.bla.message)
    std.print(fu_b.bla.value.message)


