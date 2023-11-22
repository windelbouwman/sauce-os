#################
# Demo of a generic enum type.
######

from std import print

fn main():
    let i = new_integer(23)
    let value1: Option[Integer] = Option[Integer].None()
    let value2 = Option[Integer].Some(i)

    display(value: value1)
    display(value: value2)


fn display(value: Option[Integer]):
    case value:
        Some(x):
            print("Got some: {x.value}")
        None:
            print("Got none!")

enum Option[D]:
    Some(value: D)
    None


struct Integer:
    value: int

fn new_integer(value?: int) -> Integer:
    let i_value = Integer:
        value: value
    return i_value
