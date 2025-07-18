
# Implementation of range-set
from listtype import List
from optiontype import option_is_some, option_unwrap, Option
from rangelib import Range, range_contains, range_to_string
from utils import assert, panic
from strlib import str_join
from math import max, min
from functools import zip, all

pub class IntegerSet:
	pub var ranges: List[Range]

	pub fn to_string() -> str:
		let parts: List[str] = List()
		for r in ranges:
			parts.append(range_to_string(r))
		str_join(parts, sep: ",")

	pub fn equals(other: IntegerSet) -> bool:
		integer_set_equals(a: this, b: other)

	pub fn is_empty() -> bool:
		ranges.len() == 0

	pub fn contains(value: int) -> bool:
		for range in ranges:
			if range_contains(self: range, value):
				return true
		false

	pub fn difference(other: IntegerSet) -> IntegerSet:
		integer_set_difference(self: this, other)

	pub fn union(other: IntegerSet) -> IntegerSet:
		integer_set_intersection(self: this, other)

	pub fn first() -> int:
		for range in ranges:
			return range.begin
		panic("Empty integer set!")

pub fn new_empty_int_set() -> IntegerSet:
	""" Create an new empty integer set """
	let ranges: List[Range] = List()
	integer_set_from_ranges(ranges)

pub fn new_int_set(begin: int, end: int) -> IntegerSet:
	""" Create a new integer set with a single range """
	let ranges: List[Range] = List()
	assert(condition: begin < end, message: "Range must be valid (begin < end)")
	ranges.append(Range(begin, end))
	integer_set_from_ranges(ranges)

pub fn integer_set_from_ranges(ranges: List[Range]) -> IntegerSet:
	# - check empty ranges and valid ranges. checks: 'begin < end'
	# TODO
	# - sort ranges?
	# - glue overlapping ranges?
	for range in ranges:
		assert(condition: range.begin < range.end, message: "Range must be valid (begin < end)")
	IntegerSet(ranges)

fn range_equals(a: Range, b: Range) -> bool:
	if a.begin != b.begin:
		return false
	a.end == b.end

pub fn integer_set_equals(a: IntegerSet, b: IntegerSet) -> bool:
	if a.ranges.len() != b.ranges.len():
		return false
	all(values: zip(left: a.ranges, right: b.ranges, merger: range_equals), check: is_true)

fn is_true(b?: bool) -> bool:
	b

fn integer_set_intersection(self: IntegerSet, other: IntegerSet) -> IntegerSet:
	# Create a new set with overlapping ranges
	let ranges: List[Range] = List()

	let i = self.ranges.iter()
	let j = other.ranges.iter()
	var r = i.next()
	var s = j.next()
	while option_is_some(r) and option_is_some(s):
		let rr = option_unwrap(r)
		let ss = option_unwrap(s)
		let begin = max(a: rr.begin, b: ss.begin)
		let end = min(a: rr.end, b: ss.end)
		if begin < end:
			ranges.append(Range(begin, end))

		if not (rr.end > end):
			r = i.next()

		if not (ss.end > end):
			s = j.next()

	IntegerSet(ranges)

pub fn integer_set_difference(self: IntegerSet, other: IntegerSet) -> IntegerSet:
	# Create a new set with integers, by removing other integers from self set.
	let ranges: List[Range] = List()

	let i = self.ranges.iter()
	let j = other.ranges.iter()
	var r = i.next()
	var s = j.next()

	while option_is_some(r):
		let rr = option_unwrap(r)
		if option_is_some(s):
			let ss = option_unwrap(s)
			if rr.begin >= ss.end:
				s = j.next()
			elif rr.end <= ss.begin:
				ranges.append(rr)
				r = i.next()
			else:
				if rr.begin < ss.begin:
					ranges.append(Range(begin: rr.begin, end: ss.begin))

				# if rr.end > ss.end:
				# panic("TODO: integer_set_difference")
				if rr.end > ss.end:
					r = Option.Some(Range(begin: ss.end, end: rr.end))
					s = j.next()
				else:
					r = i.next()
		else:
			ranges.append(rr)
			r = i.next()
	IntegerSet(ranges)
