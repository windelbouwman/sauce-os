
# Geometry function library.

from listtype import List
from math import abs

pub struct Point:
	x: int
	y: int

pub fn str_point(p?: Point) -> str:
	"[{p.x},{p.y}]"

pub struct Path:
	points: List[Point]

pub struct Polygon:
	path: Path

pub fn shoelace(points: List[Point]) -> float:
	# Implement shoelace algorithm to find area of polygon.
	# See: https://en.wikipedia.org/wiki/Shoelace_formula
	let n = points.len()
	var i = 0
	var s = 0
	while i < n:
		let p1 = points.get(index: i)
		var p2 = p1
		if (i + 1) < n:
			p2 = points.get(index: i + 1)
		else:
			p2 = points.get(index: 0)

		s += p1.x * p2.y - p2.x * p1.y
		i += 1

	# TODO: is abs part of shoelacing?
	abs(s) / 2.0
