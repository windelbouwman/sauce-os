
""" Signal processing routines
"""

from datatypes import List
from std import print, float_to_str
from strlib import str_join
from utils import unimplemented, log_debug
from math import sin, cos, pi

pub fn butter(n: int) -> DigitalFilter:
    """ Create a butter worth filter """
    log_debug("Creating butterworth filter of order {n}")
    let b: List[float] = List()
    let a: List[float] = List()
    b.append(1)
    let gamma = pi / (2.0 * n)
    let ak = 1.0
    a.append(ak)
    let k = 0
    while k < n:
        ak = (cos(k * gamma) / sin((k+1) * gamma)) * ak
        a.append(ak)
        k += 1
    DigitalFilter(b, a)

pub fn cheby(n: int) -> DigitalFilter:
    # Create a butter worth filter
    unimplemented("cheby")

pub class DigitalFilter:
    var b: List[float] # Numerator
    var a: List[float] # Denominator

    fn dump():
        print(s_poly_to_str(coefficients: b))
        print("-----------------")
        print(s_poly_to_str(coefficients: a))

fn s_poly_to_str(coefficients: List[float]) -> str:
    let parts: List[str] = List()
    let i = coefficients.len() - 1
    for c in coefficients:
        let part = float_to_str(c)
        if i > 0:
            part = "{part}*s^{i}"
        parts.append(part)
        i -= 1
    str_join(parts, sep: " + ")

pub fn filter(filt: DigitalFilter, values: List[float]):
    unimplemented("filter")
