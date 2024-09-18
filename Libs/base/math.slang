
from utils import panic, unimplemented

# TODO: make constant
var pi: float = 3.1415926535897932384626433

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

fn factorial(x?: int) -> int:
    if x < 0:
        panic("Factorial undefined for negative numbers like {x}")
    elif x == 0:
        return 1
    else:
        let r = x
        while x > 2:
            x -= 1
            r = r * x
        return r

fn sin(x?: float) -> float:
    if x < 0:
        # When negative, use symmetric 
        return -sin(-x)
    else:
        # Reduce to the range of 0..2pi
        let two_pi = pi * 2.0
        x = fmod(value: x, divisor: two_pi)
        
        # Select the right quarter
        if x < 0.5* pi:
            return sin_kernel(x)
        elif x < pi:
            return sin_kernel(pi - x)
        elif x < 1.5 * pi:
            return -sin_kernel(x - pi)
        else:
            return -sin_kernel(two_pi - x)

fn cos(value?: float) -> float:
    # Use sine wave, by shifting pi/2:
    return sin(value + (0.5 * pi))

fn sin_kernel(x?: float) -> float:
    """
    Implement sin on range -pi/4 .. pi/4 by using a taylor series

                 x^3   x^5   x^7
    sin(x) ~ x - --- + --- - --- + --- ....
                  3!    5!    7!
    """
    let result = 0.0
    let factor = x

    let i = 2
    while i < 40:
        result = result + factor
        # Calculate the next factor, based on the previous factor:
        factor = factor * (-(x*x) / (i*(i+1)))
        i += 2
    return result

    # let S3 = 1.0 / float(factorial(3)) #-0.166666666666666666666 # 3!
    # let S5 = 1.0 / float(factorial(5)) #0.008333333333333333333  # 5!
    # let S7 = 1.0 / float(factorial(7))
    # let S9 = 1.0 / float(factorial(9))
    # let S11 = 1.0 / float(factorial(11))
    # let S13 = 1.0 / float(factorial(13))

    # let x2 = x * x
    # let x3 = x2 * x
    # let x4 = x2 * x2
    # let x5 = x2 * x3
    # let x7 = x3 * x4
    # let x8 = x4 * x4
    # let x9 = x5 * x4
    # let x11 = x7 * x4
    # let x13 = x9 * x4
    # return x - (x3 * S3) + (x5 * S5) - (x7 * S7) + (x9 * S9) - (x11 * S11) + (x13 * S13)


fn tan(value?: float) -> float:
    # TODO: check division by 0
    return sin(value) / cos(value)

fn fmod(x?: float, divisor: float) -> float:
    if x > divisor:
        return x - int(x / divisor) * divisor
    else:
        return x

fn modulo(value: int, divisor: int) -> int:
    let x = value / divisor
    return value - (divisor * x)

# TODO: implement log10 and powf somehow!
extern "slangrt" fn powf(a?: float, b?: float) -> float
# fn powf(a?: float, b?: float) -> float:
#     panic("TODO: powf")

extern "slangrt" fn log10(value?: float) -> float
extern "slangrt" fn log2(value?: float) -> float
# fn log10(value?: float) -> float:
#     panic("TODO: log10")

# extern fn floor(value?: float) -> float
fn floor(value?: float) -> float:
    let result = float(int(value))
    if value < 0:
        result = result - 1.0
    return result

extern "slangrt" fn ceil(value?: float) -> float
# fn ceil(value?: float) -> float:
# TODO!
#     return float(value: int(value) + 1)


