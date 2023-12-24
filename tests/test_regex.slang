
from std import print
from regex import find_all
from unittest import assert_list_equals
from datatypes import vec3, vec4

fn main() -> int:
    print("OK")
    test_numbers()
    test_id_num()
    return 0

fn test_numbers():
    # TODO: fix code to allow zero at end of string
    let numbers = find_all(pattern: "[0-9]+", text: "bla bla 1337 oei ai 42 wow 0!")
    let expected = vec3("1337", "42", "0")
    assert_list_equals(numbers, expected)

fn test_id_num():
    let touching = find_all(pattern: "[a-z]+[0-9]+", text: "bla1337wow5a3w00t")
    let expected = vec4("bla1337", "wow5", "a3", "w00")
    assert_list_equals(touching, expected)

