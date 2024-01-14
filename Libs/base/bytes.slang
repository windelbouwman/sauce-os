
# Data types for bytes

from vectype import Vector, new_vector, VectorIter
from strlib import hex_char

class Bytes:
    # Immutable bytes
    var m_bytes: Vector[int]

    fn iter() -> VectorIter[int]:
        return m_bytes.iter()

    fn len() -> int:
        return m_bytes.len()
    
    fn as_hex() -> str:
        # Return bytes as hexadecimal text
        let txt = ""
        for b in m_bytes:
            txt = txt + byte_as_hex(b)
        return txt

class ByteArray:
    # Mutable bytes
    var m_bytes: Vector[int] = new_vector(default: 0)

    fn append(byte?: int):
        m_bytes.append(byte)
    
    fn extend(bytes?: Bytes):
        for b in bytes.m_bytes:
            append(b)

    fn pack32_le(value?: int):
        append(value & 0xFF)
        append((value >> 8) & 0xFF)
        append((value >> 16) & 0xFF)
        append((value >> 24) & 0xFF)

    fn pack16_be(value?: int):
        append((value & 0xff00) >> 8)
        append(value & 0xff)

    fn iter() -> VectorIter[int]:
        return m_bytes.iter()

    fn len() -> int:
        return m_bytes.len()

    fn to_bytes() -> Bytes:
        return Bytes(m_bytes)
    
    fn as_hex() -> str:
        return to_bytes().as_hex()

fn byte_as_hex(byte?: int) -> str:
    let c1 = hex_char(byte & 0xF)
    let c2 = hex_char((byte & 0xF0) >> 4)
    return "{c2}{c1}"
