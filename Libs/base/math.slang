

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

fn modulo(value: int, divisor: int) -> int:
    let x = value / divisor
    return value - (divisor * x)

