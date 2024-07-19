
# Data types for bytes

from std import str_len, str_slice, ord, chr, str_get
from utils import assert
from vectype import Vector, new_vector, VectorIter
from datatypes import Option
from strlib import hex_char, hex_to_int

class Bytes:
    # Immutable bytes
    var m_bytes: Vector[uint8]

    fn iter() -> ByteIter:
        return ByteIter(m_iter: m_bytes.iter())

    fn len() -> int:
        return m_bytes.len()
    
    fn get(index: int) -> int:
        return int(m_bytes[index])

    fn as_hex() -> str:
        # Return bytes as hexadecimal text
        let txt = ""
        for b in m_bytes:
            txt = txt + byte_as_hex(b)
        return txt
    
    fn into_reader() -> ByteReader:
        return ByteReader(m_bytes: this)

class ByteIter:
    var m_iter: VectorIter[uint8]

    fn next() -> Option[int]:
        case m_iter.next():
            Some(value):
                return Option.Some(value: int(value))
            None:
                return Option.None()

class ByteReader:
    # read byte at a time
    var m_bytes: Bytes
    var m_index: int = 0

    fn read_bytes(size: int) -> Bytes:
        let i = 0
        let ba = ByteArray()
        while i < size:
            ba.append(read_byte())
            i += 1
        return ba.to_bytes()

    fn read_byte() -> int:
        assert(condition: m_index < m_bytes.m_bytes.len(), message: "Cannot read past end of bytes")
        let value = m_bytes[m_index]
        m_index += 1
        return value

    fn read_u16_be() -> int:
        let b1 = read_byte()
        let b2 = read_byte()
        return (b1 << 8) | b2

    fn read_u16_le() -> int:
        let b1 = read_byte()
        let b2 = read_byte()
        return (b2 << 8) | b1

    fn read_u32_be() -> int:
        let b1 = read_byte()
        let b2 = read_byte()
        let b3 = read_byte()
        let b4 = read_byte()
        return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4

    fn read_u32_le() -> int:
        let b1 = read_byte()
        let b2 = read_byte()
        let b3 = read_byte()
        let b4 = read_byte()
        return (b4 << 24) | (b3 << 16) | (b2 << 8) | b1

class ByteArray:
    # Mutable bytes
    var m_bytes: Vector[uint8] = new_vector(default: uint8(0))

    fn append(byte?: int):
        m_bytes.append(uint8(byte))

    fn get(index: int) -> int:
        return int(m_bytes[index])

    fn extend(bytes?: Bytes):
        for b in bytes.m_bytes:
            append(int(b))

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

    fn pack_u16_be(value?: int):
        append((value & 0xff00) >> 8)
        append(value & 0xff)

    fn iter() -> ByteIter:
        return ByteIter(m_iter: m_bytes.iter())

    fn len() -> int:
        return m_bytes.len()

    fn to_bytes() -> Bytes:
        return Bytes(m_bytes)
    
    fn as_hex() -> str:
        return to_bytes().as_hex()

fn byte_as_hex(byte?: uint8) -> str:
    let c1 = hex_char(int(byte) & 0xF)
    let c2 = hex_char((int(byte) & 0xF0) >> 4)
    return "{c2}{c1}"

fn bytes_from_hex_text(text: str) -> Bytes:
    let output = ByteArray()
    let n = str_len(text)
    let i = 0
    while i < n:
        assert(condition: i + 1 < n, message: "Hexadecimal text must contain whole bytes")
        let part = str_slice(text, begin: i, end: i + 2)
        output.append(hex_to_int(hextext: part))
        i += 2
    return output.to_bytes()

fn new_bytes() -> Bytes:
    let output = ByteArray()
    return output.to_bytes()

fn fill_bytes(n: int, fill: int) -> Bytes:
    let output = ByteArray()
    while n > 0:
        output.append(fill)
        n -= 1
    return output.to_bytes()

fn bytes_from_ascii(text: str) -> Bytes:
    let output = ByteArray()
    let n = str_len(text)
    let i = 0
    while i < n:
        let c = str_get(text, index: i)
        output.append(ord(c))
        i += 1
    return output.to_bytes()

fn bytes_to_ascii(data: Bytes) -> str:
    # Interpret bytes as ascii data
    let result = ""
    for b in data:
        result = result + "{chr(b)}"
    return result
