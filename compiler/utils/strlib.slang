
from datatypes import List
from std import str_slice, str_get, str_len, ord
from utils import assert, panic

fn split_string(value: str, sep: char) -> List[str]:
    let size = str_len(value)
    let start = 0
    let cur = 0
    let parts: List[str] = List()
    while cur < size:
        let c = str_get(value, index: cur)
        if c == sep:
            parts.append(str_slice(value, begin: start, end: cur))
            cur += 1
            start = cur
        else:
            cur += 1
    parts.append(str_slice(value, begin: start, end: cur))
    return parts

fn string_compare(a: str, b: str) -> bool:
    return str_comparison(a, b) < 0

fn str_repeat(text: str, count: int) -> str:
    let result = ""
    let i = 0
    while i < count:
        i += 1
        result = result + text
    return result

fn str_pad_right(text: str, length: int, fill: str) -> str:
    let result = text
    while str_len(result) < length:
        result = result + fill
    return result

fn str_join(parts: List[str], sep: str) -> str:
    let x = ""
    let counter = parts.len()
    for part in parts:
        # TODO: allow += on string variables.
        x = x + part
        if counter > 1:
            x = x + sep
            counter -= 1
    return x

fn hex_to_int(hextext: str) -> int:
    # Convert hex text
    let n = str_len(hextext)
    assert(condition: n > 0, message: "Hex string must be at least a single digit.")
    let index = 0
    let value = 0
    while index < n:
        let c = str_get(hextext, index)
        let o = ord(c)

        let cval = 0
        if (o >= 48) and (o <= 57):     # 0..9
            cval = o - 48
        elif (o >= 65) and (o <= 70):   # A..F
            cval = o - 55
        elif (o >= 97) and (o <= 102):  # a..f
            cval = o - 87
        else:
            panic("Invalid hex char: {c}")
        value = value * 16 + cval
        index += 1
    return value

fn is_digit(c: char) -> bool:
    # Check if a character is a digit.
    let o = ord(value: c)
    return (o >= 48) and (o <= 57)

fn is_hex_digit(c: char) -> bool:
    # Check if a character is a hex digit.
    let o = ord(value: c)
    if (o >= 48) and (o <= 57):     # 0..9
        return true
    elif (o >= 65) and (o <= 70):   # A..F
        return true
    elif (o >= 97) and (o <= 102):  # a..f
        return true
    else:
        return false

# TODO: duplicate with rt_str_compare in C
fn str_comparison(a: str, b: str) -> int:
    let index = 0
    let n_a = str_len(a)
    let n_b = str_len(b)
    let n = n_a
    if n_b < n:
        n = n_b
    while index < n:
        index += 1
        let c_a = ord(str_get(a, index))
        let c_b = ord(str_get(b, index))
        if c_a < c_b:
            return -1
        elif c_a > c_b:
            return 1
    return 0

fn split_lines(text: str) -> List[str]:
    # TODO: use split_string here?
    let lines: List[str] = List()
    let line_start = 0
    let n = str_len(text)
    let index = 0
    while index < n:
        if ord(str_get(text, index)) == 10:
            # New line!
            if line_start < index:
                lines.append(str_slice(value: text, begin: line_start, end: index))
            else:
                lines.append("")
            line_start = index + 1
        index += 1
    if index > line_start:
        lines.append(str_slice(value: text, begin: line_start, end: index))
    return lines
