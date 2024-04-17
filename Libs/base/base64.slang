
# Implement base64 encoding scheme

from utils import unimplemented, panic
from math import modulo
from bytes import Bytes, ByteArray
from std import str_get, str_len, ord

fn base64_encode(data: Bytes) -> str:
    # Encode given data as base64 text
    let base64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    let i = 0
    let data_length = data.len()
    let pad_count = modulo(value: data_length, divisor: 3)
    let result = ""
    while i < data_length:
        # Gather 3 bytes into a 24 bits number:
        let n = (data.get(index: i) << 16)
        if i + 1 < data_length:
            n += (data.get(index: i + 1) << 8)
        if i + 2 < data_length:
            n += data.get(index: i + 2)


        # Split 24 bits into 4 groups of 6 bits
        let n0 = (n >> 18) & 63
        let n1 = (n >> 12) & 63
        let n2 = (n >> 6) & 63
        let n3 = n & 63
        result = result + "{str_get(text: base64chars, index: n0)}{str_get(text: base64chars, index: n1)}"
        if i + 1 < data_length:
            result = result + "{str_get(text: base64chars, index: n2)}"
        if i + 2 < data_length:
            result = result + "{str_get(text: base64chars, index: n3)}"

        i += 3

    # Append padding with '='
    if pad_count > 0:
        while pad_count < 3:
            result = result + "="
            pad_count += 1
    return result

fn base64_decode(text: str) -> Bytes:
    # Decode base64 text into bytes
    # unimplemented("base64_decode")
    let result = ByteArray()
    let buf = 0
    let bufsize = 0

    let i = 0
    let n = str_len(text)
    while i < n:
        # Get character:
        let c = ord(str_get(text, index: i))
        i += 1

        let v = 0
        if c >= 65 and c <= 90:
            # A .. Z
            v = c - 65
        elif c >= 97 and c <= 122:
            # a .. z
            v = c - 97 + 26
        elif c >= 48 and c <= 57:
            # 0 .. 9
            v = c + 4
        elif c == 43:
            # '+'
            v = 62
        elif c == 47:
            # '/'
            v = 63
        elif c == 10 or c == 13 or c == 32:
            # Skip newlines and whitespace
            continue
        elif c == 61:
            # '='
            break
        else:
            # TODO: create exception instead of panic
            panic("Invalid base64 char: {c}!")
        buf = (buf << 6) | v
        bufsize += 1
        if bufsize == 4:
            # Split 24 bit value into 3 bytes
            result.append((buf >> 16) & 0xFF)
            result.append((buf >> 8) & 0xFF)
            result.append(buf & 0xFF)
            bufsize = 0
            buf = 0
    
    if bufsize == 3:
        result.append((buf >> 10) & 0xFF)
        result.append((buf >> 2) & 0xFF)
    elif bufsize == 2:
        result.append((buf >> 4) & 0xFF)

    return result.to_bytes()


