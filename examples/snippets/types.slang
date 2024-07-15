
# Example with some basic types
from std import print

fn main() -> int:
    let a: int = 1
    let b: float = 2.0
    let c: str = "drie"
    let d: uint8 = uint8(value: 4)
    let e: uint16 = uint16(value: 5)
    let f: uint32 = uint32(value: 6)
    let g: uint64 = uint64(value: 7)
    let h: int8 = int8(value: 8)
    let i: int16 = int16(value: 9)
    let j: int32 = int32(value: 10)
    let k: int64 = int64(value: 11)
    let l: float32 = float32(value: 12.12)
    let m: float64 = 13.13

    print("a = {a}")
    print("c = {c}")

    let ee = add16(a: uint16(value: 7), b: e)
    # d = 255
    return 0

fn add16(a: uint16, b: uint16) -> uint16:
    return a + b
