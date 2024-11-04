from std import print
import std

struct Bla[T]:
    value: T
    x: int

struct I:
    i: int

struct S:
    s: str

fn main() -> int:
    
    let i = I:
        i: 12
    
    let s = S:
        s: "w00t"

    #let bla_i = Bla[I]:
    #    value: i
    #    x: 2

    let bla_i: Bla[I] = new_bla(v2: i, x2: 3)

    #let bla_s = Bla[S]:
    #    value: s
    #    x: 3
    
    let bla_s: Bla[S] = new_bla(v2: s, x2: 3)

    print("{bla_i.value.i}")
    print(get_v(v: bla_s).s)

    let bla_i2 = new_bla(v2: 2, x2: 3)
    print("{get_v(v: bla_i2)}")
    # print(bla_s2.value.s)
    0

fn new_bla[T](v2: T, x2: int) -> Bla[T]:
    Bla[T]:
        value: v2
        x: x2

fn get_v[T](v: Bla[T]) -> T:
    v.value
