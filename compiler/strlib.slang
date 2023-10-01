
from datatypes import List
from std import str_slice, str_get, str_len, ord

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
