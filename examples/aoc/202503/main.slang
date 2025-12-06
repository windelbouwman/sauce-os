"""
Advent of code 2025 day 3.

https://adventofcode.com/2025/day/3
"""
from std import print, read_file, str_slice, str_len, ord, get_arg
from strlib import trim, split_string, str_to_int, split_lines
from math import modulo
from listtype import List
from vectype import Vector, new_vector
from utils import panic

type Bank = Vector[int]

pub fn main() -> int:
	let banks = read_banks(filename: get_arg(arg: 0))
	part1(banks)
	part2(banks)
	0

fn read_banks(filename: str) -> List[Bank]:
	let text = read_file(filename)
	let banks: List[Vector[int]] = List()
	for line in split_lines(text):
		line = trim(line)
		if str_len(text: line) == 0:
			continue
		let bank: Vector[int] = new_vector()
		for c in line:
			let joltage = ord(c) - ord('0')
			bank.append(joltage)
		banks.append(bank)
	banks

fn part1(banks: List[Bank]):
	let s = sum_max_joltages(banks, n: 2)
	print("Part 1: {s}")

fn part2(banks: List[Bank]):
	let s = sum_max_joltages(banks, n: 12)
	print("Part 2: {s}")

fn sum_max_joltages(banks: List[Bank], n: int) -> int:
	var s = 0
	for bank in banks:
		s += find_max_joltage(bank, n)
	s

fn find_max_joltage(bank: Bank, n: int) -> int:
	var value = 0
	var begin = 0
	var end = bank.len() - n + 1
	var i = 0
	while i < n:
		let pos = find_max_index(bank, begin, end)
		value = value * 10 + bank[pos]
		begin = pos + 1
		end = end + 1
		i += 1
	value

fn find_max_index(bank: Bank, begin: int, end: int) -> int:
	var max_index = begin
	var max_value = bank[max_index]
	var index = begin + 1
	while index < end:
		let value = bank[index]
		if value > max_value:
			max_index = index
			max_value = value
		index += 1
	max_index
