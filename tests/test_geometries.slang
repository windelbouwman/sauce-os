
from datatypes import list4, list5
from std import print
from shapelib import shoelace, Point
from unittest import assert_almost_equals

pub fn main() -> int:
    test_shoelace_square()
    test_shoelace_wikipedia_example()
    print("OK")
    0

fn test_shoelace_square():
    let p1 = Point(x: 1, y: 1)
    let p2 = Point(x: 1, y: 3)
    let p3 = Point(x: 3, y: 3)
    let p4 = Point(x: 3, y: 1)
    let points = list4(p1, p2, p3, p4)
    let A = shoelace(points)
    assert_almost_equals(A, 4)

fn test_shoelace_wikipedia_example():
    # Test example from wikipedia:
    # See: https://en.wikipedia.org/wiki/Shoelace_formula
    let p1 = Point(x: 1, y: 6)
    let p2 = Point(x: 3, y: 1)
    let p3 = Point(x: 7, y: 2)
    let p4 = Point(x: 4, y: 4)
    let p5 = Point(x: 8, y: 5)
    let points = list5(p1, p2, p3, p4, p5)
    let A = shoelace(points)
    assert_almost_equals(A, 16.5)
