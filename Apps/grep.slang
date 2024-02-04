
# Grep
# 'grep' program, using regular expressions.

import std
from strlib import split_lines
from regex import find

fn main() -> int:
    let filename = "input.txt"
    let pattern = "[0-9]+"
    let text = std.read_file(filename)

    for line in split_lines(text):
        case find(pattern, text: line):
            Some(m):
                std.print(line)
            None:
                pass

    return 0
