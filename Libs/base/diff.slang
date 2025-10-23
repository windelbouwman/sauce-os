"""
Implement diff using Myers linear space algorithm

left variables: a, n, x, left, right
right variables: b, m, y, top, bottom

Use the relation k = x - y

Implemented while reading this blog:
https://blog.jcoglan.com/2017/04/25/myers-diff-in-linear-space-implementation/

"""

from logging import log_debug
from utils import panic
from listtype import List
from hashmap import HashMap, new_hashmap_int, str_eq, int_eq
from vectype import Vector, new_vector, new_vector_of_size

pub fn diff_lines(a: List[str], b: List[str]) -> List[Edit[str]]:
	""" Compare two lists of strings """
	diff_items(a, b, eq: str_eq)

pub fn diff_numbers(a: List[int], b: List[int]) -> List[Edit[int]]:
	""" Compare two lists of integers """
	diff_items(a, b, eq: int_eq)

pub fn diff_items[T](a: List[T], b: List[T], eq: fn(T,T) -> bool) -> List[Edit[T]]:
	let ctx: Context[T] = Context(a, b, eq)
	let area = Area(left: 0, top: 0, right: a.len(), bottom: b.len())
	let edits: List[Edit[T]] = List()
	log_debug("Diff: n={area.right}, m={area.bottom}")
	diff_linear_space(ctx, area, edits)
	edits

pub enum Edit[T]:
	Equal(pos1: int, pos2: int, value: T)
	Insert(pos1: int, pos2: int, value: T)
	Delete(pos: int, value: T)

struct Context[T]:
	""" Diff problem context """
	a: List[T]
	b: List[T]
	eq: fn(T, T) -> bool

struct Point:
	x: int
	y: int

class Area:
	pub var left: int
	pub var top: int
	pub var right: int
	pub var bottom: int

	pub fn width() -> int:
		right - left

	pub fn height() -> int:
		bottom - top

	pub fn to_string() -> str:
		"({left},{top})-({right},{bottom})"

fn diff_linear_space[T](ctx: Context[T], area: Area, edits: List[Edit[T]]):
	""" Recursively divide and conquer the graph in subgraphs """
	log_debug("Diffing {area}")
	# Shrink search area from top-left:
	while area.left < area.right and area.top < area.bottom and ctx.eq(ctx.a[area.left], ctx.b[area.top]):
		edits.append(Edit.Equal(pos1: area.left, pos2: area.top, value: ctx.a[area.left]))
		area.left += 1
		area.top += 1

	# Shrink search area from right-bottom:
	var n_equal_after = 0
	while area.left < area.right and area.top < area.bottom and ctx.eq(ctx.a[area.right-1], ctx.b[area.bottom-1]):
		area.right -= 1
		area.bottom -= 1
		n_equal_after += 1

	let n = area.width()
	let m = area.height()
	if m > 0 and n > 0:
		log_debug("Split region {area} into 2")
		let mid_point = find_middle_snake(ctx, area)
		let top_left_area = Area(left: area.left, top: area.top, right: mid_point.x, bottom: mid_point.y)
		let bottom_right_area = Area(left: mid_point.x, top: mid_point.y, right: area.right, bottom: area.bottom)
		diff_linear_space(ctx, area: top_left_area, edits)
		diff_linear_space(ctx, area: bottom_right_area, edits)
	elif n > 0:
		var i = 0
		while i < n:
			edits.append(Edit.Delete(pos: area.left + i, value: ctx.a[area.left + i]))
			i += 1
	elif m > 0:
		var i = 0
		while i < m:
			edits.append(Edit.Insert(pos1: area.left + i, pos2: area.top + i, value: ctx.b[area.top + i]))
			i += 1

	var i = 0
	while i < n_equal_after:
		edits.append(Edit.Equal(pos1: area.right + i, pos2: area.bottom + i, value: ctx.a[area.right + i]))
		i += 1

fn find_middle_snake[T](ctx: Context[T], area: Area) -> Point:
	""" Simultaniously search paths from start and from end. """
	let n = area.width()
	let m = area.height()
	let delta = n - m
	let odd = is_odd(delta)
	let dmin = area.left - area.bottom # Minimum diagonal
	let dmax = area.right - area.top # Maximum diagonal
	let fmid = area.left - area.top # forward middle diagonal
	let bmid = area.right - area.bottom # backward middle diagonal
	log_debug("dmin={dmin}, dmax={dmax}, fmid={fmid}, bmid={bmid}")
	var fmin = fmid # forward min
	var fmax = fmid # forward max
	var bmin = bmid # backward min
	var bmax = bmid # backward max
	var vf: HashMap[int,int] = new_hashmap_int()  # v forward search
	vf.insert(key: fmid, value: area.left)
	var vb: HashMap[int,int] = new_hashmap_int()  # v backward search
	vb.insert(key: bmid, value: area.right)
	let max_d = (m + n) / 2
	var d = 0
	while d <= max_d:
		# Forward search
		fmin -= 1
		fmax += 1
		var k = fmax
		while k >= fmin:
			log_debug("Forward search k={k}, fmin={fmin}, fmax={fmax}")
			var x = 0
			if k == fmin or (k != fmax and (vf.get(key: k - 1) < vf.get(key: k + 1))):
				x = vf.get(key: k + 1)
			else:
				x = vf.get(key: k - 1) + 1
			var y = x - k
			while x < area.right and y < area.bottom and ctx.eq(ctx.a[x], ctx.b[y]):
				x += 1
				y += 1
			vf.insert(key: k, value: x)
			if odd and bmin <= k and k <= bmax and vb.get(key: k) <= x:
				return Point(x, y)
			k -= 2

		# Backward search
		bmin -= 1
		bmax += 1
		k = bmax
		while k >= bmin:
			log_debug("Backward search k={k}, bmin={bmin}, bmax={bmax}")
			var x = 0
			if k == bmin or (k != bmax and (vb.get(key: k - 1) < vb.get(key: k + 1))):
				x = vb.get(key: k + 1) - 1
			else:
				x = vb.get(key: k - 1)
			var y = x - k
			while x > area.left and y > area.top and ctx.eq(ctx.a[x - 1], ctx.b[y - 1]):
				x -= 1
				y -= 1
			vb.insert(key: k, value: x)
			if (not odd) and fmin <= k and k <= fmax and x <= vf.get(key: k):
				return Point(x, y)
			k -= 2

		d += 1
	panic("Should not get here.")

fn is_odd(x?: int) -> bool:
	""" Test if the given number is odd """
	(x & 1) == 1

pub fn is_even(x?: int) -> bool:
	""" Test if the given number is even """
	(x & 1) == 0
