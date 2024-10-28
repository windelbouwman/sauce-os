
from datatypes import List, Option
from std import str_slice, str_get, str_len, ord, chr
from utils import assert, panic, unimplemented

fn split_string2(text: str, sep: str) -> List[str]:
    """ Split string by other string """
    unimplemented("split_string2")

fn split_string(text: str, sep: char) -> List[str]:
    let size = str_len(text)
    let start = 0
    let cur = 0
    let parts: List[str] = List()
    while cur < size:
        let c = str_get(text, index: cur)
        if c == sep:
            parts.append(str_slice(text, begin: start, end: cur))
            cur += 1
            start = cur
        else:
            cur += 1
    parts.append(str_slice(text, begin: start, end: cur))
    parts

fn string_compare(a: str, b: str) -> bool:
    str_comparison(a, b) < 0

fn str_repeat(text: str, count: int) -> str:
    let result = ""
    let i = 0
    while i < count:
        i += 1
        result = result + text
    return result

fn str_pad_right(text: str, length: int, fill: str) -> str:
    let result = text
    while str_len(text: result) < length:
        result = result + fill
    return result

fn str_pad_left(text: str, length: int, fill: str) -> str:
    let result = text
    while str_len(text: result) < length:
        result = fill + result
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

fn is_space(c: char) -> bool:
    c == ' '

fn str_to_int(text?: str) -> int:
    let n = str_len(text)
    assert(condition: n > 0, message: "Integer string must be at least a single digit.")
    let index = 0
    let value = 0
    while index < n:
        let c = str_get(text, index)
        let cval = digit_to_int(c)
        value = value * 10 + cval
        index += 1
    return value

fn hex_to_int(hextext: str) -> int:
    """ Convert hex text """
    let n = str_len(text: hextext)
    assert(condition: n > 0, message: "Hex string must be at least a single digit.")
    let index = 0
    let value = 0
    while index < n:
        let c = str_get(text: hextext, index)
        value = value * 16 + hex_digit_to_int(c)
        index += 1
    return value

fn bin_to_int(bintext: str) -> int:
    """ Convert bin text to integer value
    For example, convert 101 to 5
    """
    let n = str_len(text: bintext)
    assert(condition: n > 0, message: "Binary string must be at least a single digit.")
    let index = 0
    let value = 0
    while index < n:
        let c = str_get(text: bintext, index)
        value = value * 2 + bin_digit_to_int(c)
        index += 1
    return value

fn is_digit(c: char) -> bool:
    """  Check if a character is a digit. """
    let o = ord(value: c)
    (o >= 48) and (o <= 57)

fn digit_to_int(c: char) -> int:
    let cval = ord(c)
    if (cval >= 48) and (cval <= 57):     # 0..9
        cval - 48
    else:
        panic("Invalid integer char: {c}")

fn hex_digit_to_int(c: char) -> int:
    let o = ord(c)

    if (o >= 48) and (o <= 57):     # 0..9
        o - 48
    elif (o >= 65) and (o <= 70):   # A..F
        o - 55
    elif (o >= 97) and (o <= 102):  # a..f
        o - 87
    else:
        panic("Invalid hex char: {c}")

fn is_hex_digit(c: char) -> bool:
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

fn int_to_hex_string(value?: int) -> str:
    let text = ""
    let n = 8
    while n > 0:
        let c = hex_char(value & 0xF)
        value = value / 16
        text = "{c}{text}"
        n -= 1
    return text

fn hex_char(value?: int) -> char:
    if value < 10:
        chr(value + 48)
    elif value < 16:
        chr(value + 55)
    else:
        panic("Invalid hex char value: {value}")

fn is_bin_digit(c: char) -> bool:
    # Check if a character is a binary digit.
    let o = ord(value: c)
    if (o >= 48) and (o <= 49):     # 0..1
        true
    else:
        false

fn bin_digit_to_int(c: char) -> int:
    let cval = ord(c)
    if (cval >= 48) and (cval <= 49):     # 0..1
        cval - 48
    else:
        panic("Invalid binary char: {c}")

fn trim(text?: str) -> str:
    # Trim spaces
    let i = 0
    let n = str_len(text)
    while i < n:
        let c = str_get(text, index: i)
        if c == ' ':
            i += 1
        else:
            break
    
    while n > i:
        n -= 1
        let c = str_get(text, index: n)
        if c == ' ':
            pass
        else:
            n += 1
            break

    return str_slice(text, begin: i, end: n)

fn find_char(text: str, criterium: fn(char) -> bool) -> Option[int]:
    let i = 0
    let n = str_len(text)
    while i < n:
        let c = str_get(text, index: i)
        if criterium(c):
            return Option.Some(i)
        i += 1
    return Option.None()


fn reverse_find_char(text: str, criterium: fn(char) -> bool) -> Option[int]:
    let n = str_len(text)
    let i = n
    while i > 0:
        i -= 1
        let c = str_get(text, index: i)
        if criterium(c):
            return Option.Some(i)
    return Option.None()


# TODO: duplicate with rt_str_compare in C
fn str_comparison(a: str, b: str) -> int:
    let index = 0
    let n_a = str_len(text: a)
    let n_b = str_len(text: b)
    let n = n_a
    if n_b < n:
        n = n_b
    while index < n:
        index += 1
        let c_a = ord(str_get(text: a, index))
        let c_b = ord(str_get(text: b, index))
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
                lines.append(str_slice(text, begin: line_start, end: index))
            else:
                lines.append("")
            line_start = index + 1
        index += 1
    if index > line_start:
        lines.append(str_slice(text, begin: line_start, end: index))
    return lines
