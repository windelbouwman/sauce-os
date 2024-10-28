
# Data types for bytes

from std import str_len, str_slice, ord, chr, str_get
from utils import assert, panic
from vectype import Vector, new_vector
from datatypes import Option
from strlib import hex_char, hex_digit_to_int, is_hex_digit, is_space

class Bytes:
    # Immutable bytes
    var m_bytes: Vector[uint8]

    fn len() -> int:
        m_bytes.len()
    
    fn get(index: int) -> int:
        int(m_bytes[index])
    
    fn concat(other: Bytes) -> Bytes:
        # Concatenate two byte sequences
        concat2(a: this, b: other)

    fn as_hex() -> str:
        # Return bytes as hexadecimal text
        let txt = ""
        for b in m_bytes:
            txt = txt + byte_as_hex(b)
        txt
    
    fn into_reader() -> ByteReader:
        ByteReader(m_bytes: this)

fn concat2(a: Bytes, b: Bytes) -> Bytes:
    Bytes(m_bytes: a.m_bytes.concat(other: b.m_bytes))

class ByteReader:
    # read byte at a time
    var m_bytes: Bytes
    var m_index: int = 0

    fn at_end() -> bool:
        m_index >= m_bytes.m_bytes.len()

    fn read_bytes(size: int) -> Bytes:
        let i = 0
        let ba = ByteArray()
        while i < size:
            ba.append(read_byte())
            i += 1
        ba.to_bytes()

    fn read_byte() -> int:
        if m_index < m_bytes.m_bytes.len():
            let value = m_bytes[m_index]
            m_index += 1
            value
        else:
            panic("Cannot read past end of bytes")

    fn read_u16_be() -> int:
        let b1 = read_byte()
        let b2 = read_byte()
        (b1 << 8) | b2

    fn read_u16_le() -> int:
        let b1 = read_byte()
        let b2 = read_byte()
        (b2 << 8) | b1

    fn read_u32_be() -> int:
        let b1 = read_byte()
        let b2 = read_byte()
        let b3 = read_byte()
        let b4 = read_byte()
        (b1 << 24) | (b2 << 16) | (b3 << 8) | b4

    fn read_u32_le() -> int:
        let b1 = read_byte()
        let b2 = read_byte()
        let b3 = read_byte()
        let b4 = read_byte()
        (b4 << 24) | (b3 << 16) | (b2 << 8) | b1

class ByteArray:
    # Mutable bytes
    var m_bytes: Vector[uint8] = new_vector()

    fn append(byte?: int):
        m_bytes.append(uint8(byte))

    fn get(index: int) -> int:
        int(m_bytes[index])

    fn extend(bytes?: Bytes):
        m_bytes.extend(other: bytes.m_bytes)

    fn pack_u64_le(value?: int):
        append(value & 0xFF)
        append((value >> 8) & 0xFF)
        append((value >> 16) & 0xFF)
        append((value >> 24) & 0xFF)
        append((value >> 32) & 0xFF)
        append((value >> 40) & 0xFF)
        append((value >> 48) & 0xFF)
        append((value >> 56) & 0xFF)

    fn pack_u32_le(value?: int):
        append(value & 0xFF)
        append((value >> 8) & 0xFF)
        append((value >> 16) & 0xFF)
        append((value >> 24) & 0xFF)

    fn pack_u32_be(value?: int):
        append((value >> 24) & 0xFF)
        append((value >> 16) & 0xFF)
        append((value >> 8) & 0xFF)
        append(value & 0xFF)

    fn pack_u16_le(value?: int):
        append(value & 0xff)
        append((value >> 8) & 0xFF)

    fn pack_u16_be(value?: int):
        append((value & 0xff00) >> 8)
        append(value & 0xff)

    fn len() -> int:
        m_bytes.len()

    fn to_bytes() -> Bytes:
        Bytes(m_bytes)
    
    fn as_hex() -> str:
        to_bytes().as_hex()

fn byte_as_hex(byte?: uint8) -> str:
    let c1 = hex_char(int(byte) & 0xF)
    let c2 = hex_char((int(byte) & 0xF0) >> 4)
    "{c2}{c1}"

fn bytes_from_hex_text(text: str) -> Bytes:
    let output = ByteArray()
    let n = str_len(text)
    let i = 0
    let value = 0
    let n_bits = 0
    while i < n:
        let c = str_get(text, index: i)
        if is_hex_digit(c):
            value = (value << 4) | hex_digit_to_int(c)
            n_bits += 4
            if n_bits == 8:
                output.append(value)
                value = 0
                n_bits = 0
        elif is_space(c):
            pass
        else:
            panic("Invalid hex char '{c}'")
        i += 1
    assert(condition: n_bits == 0, message: "Hexadecimal text must contain whole bytes")
    output.to_bytes()

fn new_bytes() -> Bytes:
    let output = ByteArray()
    output.to_bytes()

fn fill_bytes(n: int, fill: int) -> Bytes:
    let output = ByteArray()
    while n > 0:
        output.append(fill)
        n -= 1
    output.to_bytes()

fn bytes_from_ascii(text: str) -> Bytes:
    let output = ByteArray()
    let n = str_len(text)
    let i = 0
    while i < n:
        let c = str_get(text, index: i)
        output.append(ord(c))
        i += 1
    output.to_bytes()

fn bytes_to_ascii(data: Bytes) -> str:
    # Interpret bytes as ascii data
    let result = ""
    for b in data:
        result = result + "{chr(b)}"
    result
