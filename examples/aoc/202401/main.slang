"""
Advent of code 2024 day 1.

https://adventofcode.com/2024/day/1
"""

from std import print, read_file, get_arg
from math import abs
from strlib import str_to_int, split_string, split_lines
from listtype import List
from hashmap import HashMap, new_hashmap_int
from sorting import sort_list

pub fn main() -> int:
	let puzzle = load_file(filename: get_arg(arg: 0))
	part1(puzzle)
	part2(puzzle)
	0

struct Puzzle:
	left: List[int]
	right: List[int]

fn load_file(filename: str) -> Puzzle:
	let left: List[int] = List()
	let right: List[int] = List()
	for line in split_lines(text: read_file(filename)):
		let parts = split_string(text: line, sep: ' ')
		left.append(str_to_int(parts[0]))
		right.append(str_to_int(parts[3]))
	Puzzle(left, right)

fn part1(puzzle: Puzzle):
	let left = sort_list(puzzle.left, cmp: int_cmp)
	let right = sort_list(puzzle.right, cmp: int_cmp)
	var s = 0
	var index = 0
	while index < left.len():
		let diff = abs(left[index] - right[index])
		s += diff
		index += 1
	print("Part 1: {s}")

fn int_cmp(a: int, b: int) -> bool:
	a < b

fn part2(puzzle: Puzzle):
	let counts: HashMap[int,int] = new_hashmap_int()
	for x in puzzle.right:
		let value = if counts.contains(key: x):
			counts.get(key: x) + 1
		else:
			1
		counts.insert(key: x, value)

	var s = 0
	for x in puzzle.left:
		if counts.contains(key: x):
			s += x * counts.get(key: x)
	print("Part 2: {s}")
