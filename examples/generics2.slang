from std import print
import std

struct Bla[T]:
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

    let bla_i = new_bla(v2: i, x2: 3)

    #let bla_s = Bla[S]:
    #    value: s
    #    x: 3
    
    let bla_s = new_bla(v2: s, x2: 3)

    print("{bla_i.value.i}")
    print(get_v(v: bla_s).s)

    let bla_i2 = new_bla(v2: 2, x2: 3)
    print("{get_v(v: bla_i2)}")
    # print(bla_s2.value.s)

fn new_bla[T](v2: T, x2: int) -> Bla[T]:
    let b2 = Bla[T]:
        value: v2
        x: x2
    return b2

fn get_v[T](v: Bla[T]) -> T:
    return v.value
