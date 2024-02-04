
from utils import panic

fn min(a: int, b: int) -> int:
    if a < b:
        return a
    else:
        return b

fn max(a: int, b: int) -> int:
    if a > b:
        return a
    else:
        return b

fn abs(a?: int) -> int:
    if a < 0:
        return -a
    else:
        return a

fn fabs(a?: float) -> float:
    if a < 0:
        return -a
    else:
        return a

fn modulo(value: int, divisor: int) -> int:
    let x = value / divisor
    return value - (divisor * x)

# TODO: implement log10 and powf somehow!
extern fn powf(a?: float, b?: float) -> float
# fn powf(a?: float, b?: float) -> float:
#     panic("TODO: powf")

extern fn log10(value?: float) -> float
# fn log10(value?: float) -> float:
#     panic("TODO: log10")

fn floor(value?: float) -> float:
    return float(value: int(value))

fn ceil(value?: float) -> float:
    return float(value: int(value) + 1)


