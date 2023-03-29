from std import print
import std

struct<T> Bla:
    value: T
    x: int

struct I:
    i: int

struct S:
    s: str

fn main():
    
    let i = I:
        i: 12
    
    let s = S:
        s: "w00t"

    #let bla_i = Bla[I]:
    #    value: i
    #    x: 2

    let bla_i = new_bla(i, 3)

    #let bla_s = Bla[S]:
    #    value: s
    #    x: 3
    
    let bla_s = new_bla(s, 3)

    print("{bla_i.value.i}")
    print(bla_s.value.s)
    # print(bla_s2.value.s)

fn new_bla<T>(v2: T, x2: int) -> Bla[T]:
    let b2 = Bla[T]:
        value: v2
        x: x2
    return b2
