
from listtype import List
from optiontype import Option
from math import min
from sorting import sort_list
from std import str_slice, str_len, ord, chr
from utils import assert, panic, unimplemented

pub fn split_string2(text: str, sep: str) -> List[str]:
	""" Split string by other string """
	unimplemented("split_string2")

pub fn split_string(text: str, sep: char) -> List[str]:
	let size = str_len(text)
	var start = 0
	var cur = 0
	let parts: List[str] = List()
	while cur < size:
		let c = text[cur]
		if c == sep:
			parts.append(str_slice(text, begin: start, end: cur))
			cur += 1
			start = cur
		else:
			cur += 1
	parts.append(str_slice(text, begin: start, end: cur))
	parts

pub fn lexical_sort(values?: List[str]) -> List[str]:
	sort_list(values, cmp: string_compare)

pub fn string_compare(a: str, b: str) -> bool:
	str_comparison(a, b) < 0

pub fn str_repeat(text: str, count: int) -> str:
	var result = ""
	var i = 0
	while i < count:
		i += 1
		result = result + text
	result

pub fn str_pad_right(text: str, length: int, fill: str) -> str:
	var result = text
	while str_len(text: result) < length:
		result = result + fill
	result

pub fn str_pad_left(text: str, length: int, fill: str) -> str:
	var result = text
	while str_len(text: result) < length:
		result = fill + result
	result

pub fn str_join(parts: List[str], sep: str) -> str:
	var x = ""
	var counter = parts.len()
	for part in parts:
		# TODO: allow += on string variables.
		x = x + part
		if counter > 1:
			x = x + sep
			counter -= 1
	x

pub fn is_space(c: char) -> bool:
	c == ' '

pub fn is_tab(c: char) -> bool:
	ord(c) == 9

pub fn is_lf(c: char) -> bool:
	ord(c) == 10

fn is_whitespace(c?: char) -> bool:
	is_space(c) or is_lf(c) or ord(c) == 13

pub fn str_to_int(text?: str) -> int:
	let n = str_len(text)
	assert(condition: n > 0, message: "Integer string must be at least a single digit.")
	var negative = false
	var first = true
	var value = 0
	for c in text:
		if first and c == '-':
			negative = true
		else:
			value = value * 10 + digit_to_int(c)
		first = false
	if negative:
		-value
	else:
		value

pub fn hex_to_int(hextext: str) -> int:
	""" Convert hex text """
	let n = str_len(text: hextext)
	assert(condition: n > 0, message: "Hex string must be at least a single digit.")
	var value = 0
	for c in hextext:
		value = value * 16 + hex_digit_to_int(c)
	value

pub fn bin_to_int(bintext: str) -> int:
	""" Convert bin text to integer value
	For example, convert 101 to 5
	"""
	let n = str_len(text: bintext)
	assert(condition: n > 0, message: "Binary string must be at least a single digit.")
	var value = 0
	for c in bintext:
		value = value * 2 + bin_digit_to_int(c)
	value

pub fn is_digit(c: char) -> bool:
	"""  Check if a character is a digit. """
	let o = ord(value: c)
	(o >= 48) and (o <= 57)

pub fn digit_to_int(c: char) -> int:
	let cval = ord(c)
	if (cval >= 48) and (cval <= 57):     # 0..9
		cval - 48
	else:
		panic("Invalid integer char: {c}")

pub fn hex_digit_to_int(c: char) -> int:
	let o = ord(c)

	if (o >= 48) and (o <= 57):     # 0..9
		o - 48
	elif (o >= 65) and (o <= 70):   # A..F
		o - 55
	elif (o >= 97) and (o <= 102):  # a..f
		o - 87
	else:
		panic("Invalid hex char: {c}")

pub fn is_hex_digit(c: char) -> bool:
	""" Check if a character is a hex digit. """
	let o = ord(value: c)
	if (o >= 48) and (o <= 57):     # 0..9
		true
	elif (o >= 65) and (o <= 70):   # A..F
		true
	elif (o >= 97) and (o <= 102):  # a..f
		true
	else:
		false

pub fn int_to_hex_string(value?: int) -> str:
	var text = ""
	var n = 8
	while n > 0:
		let c = hex_char(value & 0xF)
		value /= 16
		text = "{c}{text}"
		n -= 1
	text

pub fn hex_char(value?: int) -> char:
	if value < 10:
		chr(value + 48)
	elif value < 16:
		chr(value + 55)
	else:
		panic("Invalid hex char value: {value}")

pub fn is_bin_digit(c: char) -> bool:
	# Check if a character is a binary digit.
	let o = ord(value: c)
	if (o >= 48) and (o <= 49):     # 0..1
		true
	else:
		false

pub fn bin_digit_to_int(c: char) -> int:
	let cval = ord(c)
	if (cval >= 48) and (cval <= 49):     # 0..1
		cval - 48
	else:
		panic("Invalid binary char: {c}")

pub fn trim(text?: str) -> str:
	# Trim spaces
	var i = 0
	var n = str_len(text)
	while i < n:
		if is_whitespace(text[i]):
			i += 1
		else:
			break

	while n > i:
		n -= 1
		if is_whitespace(text[n]):
			pass
		else:
			n += 1
			break

	str_slice(text, begin: i, end: n)

pub fn find_char(text: str, criterium: fn(char) -> bool) -> Option[int]:
	var i = 0
	let n = str_len(text)
	while i < n:
		let c = text[i]
		if criterium(c):
			return Option.Some(i)
		i += 1
	Option.None()


pub fn reverse_find_char(text: str, criterium: fn(char) -> bool) -> Option[int]:
	let n = str_len(text)
	var i = n
	while i > 0:
		i -= 1
		let c = text[i]
		if criterium(c):
			return Option.Some(i)
	Option.None()


# TODO: duplicate with rt_str_compare in C
fn str_comparison(a: str, b: str) -> int:
	var index = 0
	let n_a = str_len(text: a)
	let n_b = str_len(text: b)
	let n = min(a: n_a, b: n_b)
	while index < n:
		let c_a = ord(a[index])
		let c_b = ord(b[index])
		if c_a < c_b:
			return -1
		elif c_a > c_b:
			return 1
		index += 1
	0

pub fn split_lines(text: str) -> List[str]:
	# TODO: use split_string here?
	let lines: List[str] = List()
	var line_start = 0
	let n = str_len(text)
	var index = 0
	while index < n:
		if ord(text[index]) == 10:
			# New line!
			if line_start < index:
				lines.append(str_slice(text, begin: line_start, end: index))
			else:
				lines.append("")
			line_start = index + 1
		index += 1
	if index > line_start:
		lines.append(str_slice(text, begin: line_start, end: index))
	lines
