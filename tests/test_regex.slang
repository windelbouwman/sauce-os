
from std import print
from regex import find_all_text, split_at_pattern
from unittest import assert_list_equals
from datatypes import list3, list4

pub fn main() -> int:
	test_numbers()
	test_id_num()
	test_alternatives()
	test_split()
	test_invert()
	print("OK")
	0

fn test_numbers():
	let numbers = find_all_text(pattern: "-?[0-9]+", text: "bla bla 1337 oei ai -42 wow 0")
	let expected = list3("1337", "-42", "0")
	assert_list_equals(numbers, expected)

fn test_id_num():
	let touching = find_all_text(pattern: "[a-z]+[0-9]+", text: "bla1337wow5a3w00t")
	let expected = list4("bla1337", "wow5", "a3", "w00")
	assert_list_equals(touching, expected)

fn test_alternatives():
	let items = find_all_text(pattern: "[a-z]+|[0-479]+", text: "bla 7443 woei 192!")
	let expected = list4("bla", "7443", "woei", "192")
	assert_list_equals(items, expected)

fn test_split():
	let items = split_at_pattern(text: "bla 7443 woei 192!", pattern: "[0-9]+")
	let expected = list3("bla ", " woei ", "!")
	assert_list_equals(items, expected)

fn test_invert():
	let numbers = find_all_text(pattern: "[^ 0-9]+", text: "bla bla 1337 oei")
	let expected = list3("bla", "bla", "oei")
	assert_list_equals(numbers, expected)
