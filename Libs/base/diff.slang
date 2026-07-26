module base.diff
"""Implement diff using Myers linear space algorithm

left variables: a, n, x, left, right
right variables: b, m, y, top, bottom

Use the relation k = x - y

Implemented while reading this blog:
https://blog.jcoglan.com/2017/04/25/myers-diff-in-linear-space-implementation/
"""

from logging import log_debug
from utils import panic
from std import str_len, str_get, print
from listtype import List
from optiontype import Option
from vectype import Vector, new_vector_with_capacity
from hashmap import HashMap, new_hashmap_int, str_eq, int_eq, char_eq
import math
import terminal

pub fn ratio(a: str, b: str) -> float:
	"""Calculate similarity ratio between two strings.

	This has remotely to do with Levenshtein distance.

	Returns a value between 0 and 1 indicating similarity
	"""
	let n = str_len(text: a)
	let m = str_len(text: b)
	var d = 0
	for edit in diff_strings(a, b):
		case edit:
			Equal(pos1, pos2, value):
				pass
		else:
			d += 1
	1.0 - float(d) / math.max(n, m)

pub fn diff_lines(a: Vector[str], b: Vector[str]) -> List[Edit[str]]:
	"""Compare two lists of strings"""
	diff_items(a, b, eq: str_eq)

pub fn count_diff_changes[T](edits: List[Edit[T]]) -> int:
	"""Count number of changes"""
	var n_diffs = 0
	for edit in edits:
		case edit:
			Equal(pos1, pos2, values):
				pass
			Delete(pos1, pos2, values):
				n_diffs += values.len()
			Insert(pos1, pos2, values):
				n_diffs += values.len()
			Change(pos1, pos2, old_values, new_values):
				n_diffs += old_values.len() + new_values.len()
	n_diffs

pub fn render_diff(edits: List[Edit[str]], show_unchanged_lines: bool):
	"""Print diff to console"""
	for edit in edits:
		case edit:
			Equal(pos1, pos2, values):
				if show_unchanged_lines:
					print("Eq {pos1}")
					for value in values:
						print(" == {value}")
			Delete(pos1, pos2, values):
				print("{old_range_to_str(pos: pos1, size: values.len())}d{pos2}")
				for value in values:
					print("< {value}")
			Insert(pos1, pos2, values):
				print("{pos1}a{old_range_to_str(pos: pos2, size: values.len())}")
				for value in values:
					print("> {value}")
			Change(pos1, pos2, old_values, new_values):
				print("{old_range_to_str(pos: pos1, size: old_values.len())}c{old_range_to_str(pos: pos2, size: new_values.len())}")
				for value in old_values:
					print("< {value}")
				print("---")
				for value in new_values:
					print("> {value}")

fn old_range_to_str(pos: int, size: int) -> str:
	str(pos + 1) if size == 1 else "{pos + 1},{pos + size}"

struct UnifiedBlock:
	"""Single block of unified diff output"""
	pos1: int
	size1: int
	pos2: int
	size2: int
	lines: List[str]
	has_deltas: bool

fn new_unified_block(pos1: int, pos2: int) -> UnifiedBlock:
	UnifiedBlock(pos1, size1: 0, pos2, size2: 0, lines: List(), has_deltas: false)

pub fn show_unified(edits: List[Edit[str]], context: int):
	"""Create unified output, with a given amount of context"""
	var block = new_unified_block(pos1: 0, pos2: 0)
	for edit in edits:
		case edit:
			Equal(pos1, pos2, values):
				if block.lines.is_empty():
					let n = math.min(a: values.len(), b: context)
					var index = values.len() - n
					while index < values.len():
						let value = values.get(index)
						index += 1
						block.lines.append(" {value}")
					block.size1 += n
					block.size2 += n
				else:
					if values.len() > context * 2:
						# Add context lines to end
						var index = 0
						while index < context:
							let value = values.get(index)
							index += 1
							block.lines.append(" {value}")
						block.size1 += context
						block.size2 += context
						emit_block(block)

						# New block
						block = new_unified_block(pos1: pos1 + values.len() - context, pos2: pos2 + values.len() - context)

						index = values.len() - context
						while index < values.len():
							let value = values.get(index)
							index += 1
							block.lines.append(" {value}")
						block.size1 += context
						block.size2 += context
					else:
						# We must include all lines
						block.size1 += values.len()
						block.size2 += values.len()
						for value in values:
							block.lines.append(" {value}")
			Delete(pos1, pos2, values):
				block.size1 += values.len()
				block.has_deltas = true
				for value in values:
					block.lines.append(terminal.colored_text(text: "-{value}", color: terminal.Color.Red()))
			Insert(pos1, pos2, values):
				block.size2 += values.len()
				block.has_deltas = true
				for value in values:
					block.lines.append(terminal.colored_text(text: "+{value}", color: terminal.Color.Green()))
			Change(pos1, pos2, old_values, new_values):
				block.size1 += old_values.len()
				block.size2 += new_values.len()
				block.has_deltas = true
				for value in old_values:
					block.lines.append(terminal.colored_text(text: "-{value}", color: terminal.Color.Red()))
				for value in new_values:
					block.lines.append(terminal.colored_text(text: "+{value}", color: terminal.Color.Green()))
	emit_block(block)

fn pos_size_to_str(pos: int, size: int) -> str:
	str(pos + 1) if size == 1 else "{pos + 1},{size}"

fn emit_block(block: UnifiedBlock):
	if block.lines.is_empty() or not block.has_deltas:
		return
	print(terminal.colored_text(text: "@@ -{pos_size_to_str(pos: block.pos1, size: block.size1)} +{pos_size_to_str(pos: block.pos2, size: block.size2)} @@", color: terminal.Color.Cyan()))
	for line in block.lines:
		print(line)

pub fn diff_numbers(a: Vector[int], b: Vector[int]) -> List[Edit[int]]:
	"""Compare two lists of integers"""
	diff_items(a, b, eq: int_eq)

pub fn diff_strings(a: str, b: str) -> List[Edit[char]]:
	"""Compare two strings"""
	diff_chars(a: str_to_char_vector(a), b: str_to_char_vector(b))

fn str_to_char_vector(s?: str) -> Vector[char]:
	let n = str_len(text: s)
	let r: Vector[char] = new_vector_with_capacity(capacity: n)
	var i = 0
	while i < n:
		r.append(str_get(text: s, index: i))
		i += 1
	r

pub fn diff_chars(a: Vector[char], b: Vector[char]) -> List[Edit[char]]:
	"""Compare two lists of chars"""
	diff_items(a, b, eq: char_eq)

pub fn diff_items[T](a: Vector[T], b: Vector[T], eq: fn(T, T) -> bool) -> List[Edit[T]]:
	let ctx: Context[T] = Context(a, b, eq)
	let area = Area(left: 0, top: 0, right: a.len(), bottom: b.len())
	let edits: List[Edit[T]] = List()
	log_debug("Diff: n={area.right}, m={area.bottom}")
	diff_linear_space(ctx, area, edits)
	group_edits(edits)

pub enum Edit[T]:
	Equal(pos1: int, pos2: int, values: Vector[T])
	Insert(pos1: int, pos2: int, values: Vector[T])
	Delete(pos1: int, pos2: int, values: Vector[T])
	Change(pos1: int, pos2: int, old_values: Vector[T], new_values: Vector[T])

struct Context[T]:
	"""Diff problem context"""
	a: Vector[T]
	b: Vector[T]
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
	"""Recursively divide and conquer the graph in subgraphs"""
	log_debug("Diffing {area}")
	# Shrink search area from top-left:
	var n_equal_before = 0
	while area.left < area.right and area.top < area.bottom and ctx.eq(ctx.a[area.left], ctx.b[area.top]):
		n_equal_before += 1
		area.left += 1
		area.top += 1
	if n_equal_before > 0:
		let values = ctx.a.slice(offset: area.left - n_equal_before, amount: n_equal_before)
		edits.append(Edit.Equal(pos1: area.left - n_equal_before, pos2: area.top - n_equal_before, values))

	# Shrink search area from right-bottom:
	var n_equal_after = 0
	while area.left < area.right and area.top < area.bottom and ctx.eq(ctx.a[area.right - 1], ctx.b[area.bottom - 1]):
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
		let values = ctx.a.slice(offset: area.left, amount: n)
		edits.append(Edit.Delete(pos1: area.left, pos2: area.top, values))
	elif m > 0:
		let values = ctx.b.slice(offset: area.top, amount: m)
		edits.append(Edit.Insert(pos1: area.left, pos2: area.top, values))

	if n_equal_after > 0:
		let values = ctx.a.slice(offset: area.right, amount: n_equal_after)
		edits.append(Edit.Equal(pos1: area.right, pos2: area.bottom, values))

fn find_middle_snake[T](ctx: Context[T], area: Area) -> Point:
	"""Simultaniously search paths from start and from end."""
	let n = area.width()
	let m = area.height()
	let delta = n - m
	let odd = is_odd(delta)
	let dmin = area.left - area.bottom  # Minimum diagonal
	let dmax = area.right - area.top  # Maximum diagonal
	let fmid = area.left - area.top  # forward middle diagonal
	let bmid = area.right - area.bottom  # backward middle diagonal
	log_debug("dmin={dmin}, dmax={dmax}, fmid={fmid}, bmid={bmid}")
	var fmin = fmid  # forward min
	var fmax = fmid  # forward max
	var bmin = bmid  # backward min
	var bmax = bmid  # backward max
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
	"""Test if the given number is odd"""
	(x & 1) == 1

fn is_even(x?: int) -> bool:
	"""Test if the given number is even"""
	(x & 1) == 0

fn group_edits[T](edits: List[Edit[T]]) -> List[Edit[T]]:
	"""Post process edits"""
	edits = fold_edits(edits, fold_func: merge_two_edits)
	fold_edits(edits, fold_func: add_change_edits)

fn fold_edits[T](edits: List[Edit[T]], fold_func: fn(Edit[T], Edit[T]) -> Option[Edit[T]]) -> List[Edit[T]]:
	"""Try to merge edits by using the given fold_func."""
	let result: List[Edit[T]] = List()
	for edit in edits:
		if result.is_empty():
			result.append(edit)
		else:
			let last: Edit[T] = result.last()
			case fold_func(first: last, second: edit):
				Some(combined):
					result.drop_last()
					result.append(combined)
				None:
					result.append(edit)
	result

fn merge_two_edits[T](first: Edit[T], second: Edit[T]) -> Option[Edit[T]]:
	"""Try to merge two edits into a single edit"""
	case first:
		Equal(pos1, pos2, values):
			Option.None()
		Delete(first_pos1, first_pos2, first_values):
			case second:
				Delete(second_pos1, second_pos2, second_values):
					if first_pos1 + first_values.len() == second_pos1 and first_pos2 == second_pos2:
						let new_values = first_values.concat(other: second_values)
						Option.Some(Edit.Delete(pos1: first_pos1, pos2: first_pos2, values: new_values))
					else:
						Option.None()
			else:
				Option.None()
		Insert(pos1, pos2, a_values):
			case second:
				Insert(second_pos1, second_pos2, second_values):
					if pos1 == second_pos1 and pos2 + a_values.len() == second_pos2:
						let new_values = a_values.concat(other: second_values)
						Option.Some(Edit.Insert(pos1, pos2, values: new_values))
					else:
						Option.None()
			else:
				Option.None()
	else:
		Option.None()

fn add_change_edits[T](first: Edit[T], second: Edit[T]) -> Option[Edit[T]]:
	case first:
		Delete(first_pos1, first_pos2, first_values):
			case second:
				Insert(b_pos1, b_pos2, b_values):
					Option.Some(Edit.Change(first_pos1, b_pos2, first_values, b_values))
			else:
				Option.None()
	else:
		Option.None()
