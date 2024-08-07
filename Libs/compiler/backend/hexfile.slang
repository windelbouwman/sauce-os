
# Implement INTEL HEX format.
# See also: https://en.wikipedia.org/wiki/Intel_HEX

from std import print
from datatypes import List
from bytes import ByteArray, Bytes
from utils import assert

class HexFile:
    var m_lines: List[HexLine] = List()

    fn add_bytes(address: int, data: Bytes):
        # Add bytes into hex file
        let offset = 0

        for part in to_chunks(data):
            add_record(address: address + offset, record: 0, data: part)
            offset += part.len()
    
    fn add_eof():
        add_record(address: 0, record: 1, data: ByteArray().to_bytes())
    
    fn add_record(address: int, record: int, data: Bytes):
        let line = HexLine(address: address, record, data)
        m_lines.append(line)

    fn print_hex_file():
        for line in m_lines:
            print(hex_line_to_text(line))

fn to_chunks(data: Bytes) -> List[Bytes]:
    let parts: List[Bytes] = List()
    let part = ByteArray()
    for b in data:
        assert(condition: b < 0x100, message: "Byte must be smaller than 256")
        part.append(b)
        if part.len() > 7:
            parts.append(part.to_bytes())
            part = ByteArray()

    if part.len() > 0:
        parts.append(part.to_bytes())

    return parts

struct HexLine:
    address: int
    record: int
    data: Bytes

fn hex_line_to_text(line: HexLine) -> str:
    let x = ByteArray()
    x.append(line.data.len())
    x.pack_u16_be(line.address)
    x.append(line.record)
    x.extend(line.data)
    let crc = 0
    for b in x:
        crc += b
    crc = (0x100 - (crc & 0xff)) & 0xff
    x.append(crc)
    let txt = x.as_hex()
    return ":{txt}"

