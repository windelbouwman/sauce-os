
from utils import panic, unimplemented

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

# TODO: do something clever with traits / interfaces / generics
fn fmin(a?: float, b?: float) -> float:
    if a < b:
        return a
    else:
        return b

fn fmax(a?: float, b?: float) -> float:
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

fn sin(value?: float) -> float:
    unimplemented("sin")

fn cos(value?: float) -> float:
    unimplemented("cos")

fn tan(value?: float) -> float:
    # TODO: check division by 0
    return sin(value) / cos(value)

fn modulo(value: int, divisor: int) -> int:
    let x = value / divisor
    return value - (divisor * x)

# TODO: implement log10 and powf somehow!
extern "runtime" fn powf(a?: float, b?: float) -> float
# fn powf(a?: float, b?: float) -> float:
#     panic("TODO: powf")

extern "runtime" fn log10(value?: float) -> float
# fn log10(value?: float) -> float:
#     panic("TODO: log10")

# extern fn floor(value?: float) -> float
fn floor(value?: float) -> float:
    let result = float(value: int(value))
    if value < 0:
        result = result - 1.0
    return result

extern "runtime" fn ceil(value?: float) -> float
# fn ceil(value?: float) -> float:
# TODO!
#     return float(value: int(value) + 1)


