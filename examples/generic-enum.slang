#################
# Demo of a generic enum type.
######

import std
from std import print, int_to_str

fn main():
    let i = new_integer(23)
    let value1: Option[Integer] = Option[Integer].None()
    let value2 = Option[Integer].Some(i)

    display(value1)
    display(value2)


fn display(value: Option[Integer]):
    case value:
        Some(x):
            print("Got some: {x.value}")
        None:
            print("Got none!")

enum<D> Option:
    Some(D)
    None


struct Integer:
    value: int

fn new_integer(value: int) -> Integer:
    let i_value = Integer:
        value: value
    return i_value
