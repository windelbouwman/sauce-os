
from std import float_to_str, print
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
    while i < 30:
        result = result + factor
        # Calculate the next factor, based on the previous factor:
        factor = factor * (-(x*x) / (i*(i+1)))
        i += 2
    return result

fn tan(value?: float) -> float:
    # TODO: check division by 0
    return sin(value) / cos(value)

fn fmod(x?: float, divisor: float) -> float:
     # TODO: how about negative numbers?
    if x > divisor:
        return x - int(x / divisor) * divisor
    else:
        return x

fn modulo(value: int, divisor: int) -> int:
    let x = value / divisor
    return value - (divisor * x)

fn powf(x?: float, y?: float) -> float:
    """ Raise x to the power of y.

    Implemented as:
    x^y = e^(y*log(x))

    This follow from: x^y = exp(log(x))^y = exp(y * log(x))
    """
    return exp(y * log(x))

fn log10(x?: float) -> float:
    return log(x) / log(10)

fn log2(x?: float) -> float:
    return log(x) / log(2)

fn log(x?: float) -> float:
    """ Natural logarithm

    See: https://en.wikipedia.org/wiki/Natural_logarithm
    For implementation algorithm: https://ben.land/post/2021/02/24/power-without-math-lib/

    Use the series:
                  2       ?
    log(x) = Sum ----- * (---)^(2n+1)
                 2*n+1    ?
    """

    let q = 3.0
    if x > 0:
        if x > q:
            # For larger x, use the trick:
            # log(x) = log(p*q^r) = log(p) + r * log(q)
            let r = 0
            while x > q:
                x = x / q
                r += 1
            return log(x) + r * log(q)
        else:
            # range 0 .. 1
            let ratio = (x - 1) / (x + 1)
            let F = ratio
            let y = 0.0
            let n = 1
            loop:
                let term = F / n
                y = y + term
                if fabs(term) < 1e-17:
                    break
                F = F * ratio * ratio
                n += 2
            return 2 * y
    else:
        panic("log({float_to_str(x)}) is undefined")

fn exp(x?: float) -> float:
    """ Use Taylor series:

              x^1   x^2   x^3
    e^x = 1 + --- + --- + --- + ...
               1!    2!    3!
    
    """

    if x < 0:
        # exp(-z) = 1/exp(z)
        return 1/exp(-x)
    elif x > 1:
        # Use the fact that:
        # e^x = (e^(x/3))^3
        let r = exp(x / 3.0)
        return r * r * r
    else:
        let sum = 1.0
        let term = 1.0
        let n = 1
        loop:
            term = term * (x / float(n))
            sum = sum + term
            n += 1
            # print("n = {n}")
            if term < 1e-18:
                break
            if n > 100:
                break
        return sum

fn floor(value?: float) -> float:
    let i = int(value)
    if float(i) == value:
        return value
    elif value < 0:
        return float(i - 1)
    else:
        return float(int(value))

fn ceil(value?: float) -> float:
    let i = int(value)
    if float(i) == value:
        return value
    elif value < 0:
        return float(i)
    else:
        return float(i + 1)
