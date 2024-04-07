
# See RFC-1952: GZIP file format.

from datetime import unix_to_str
from std import print
from utils import unimplemented, assert
from bytes import Bytes, ByteReader
from deflate import new_deflate_decoder, BitReader

fn gzip_decompress(data?: Bytes) -> Bytes:
    # Handle the gzip header.
    let reader = data.into_reader()
    let id1 = reader.read_byte()
    let id2 = reader.read_byte()
    assert(condition: id1 == 0x1f, message: "Expect ID1: 0x1F")
    assert(condition: id2 == 0x8B, message: "Expect ID1: 0x8B")
    let cm = reader.read_byte()
    assert(condition: cm == 8, message: "Expect only DEFLATE (8) as compression")
    let flg = reader.read_byte()
    let mtime = reader.read_u32_le()
    let xfl = reader.read_byte()
    let os = reader.read_byte()
    print("OS = {os} mtime={unix_to_str(seconds: mtime)}")

    # bit 0   FTEXT
    # bit 1   FHCRC
    # bit 2   FEXTRA
    # bit 3   FNAME
    # bit 4   FCOMMENT

    if (flg >> 2) & 1 == 1:  # FEXTRA
        unimplemented("FEXTRA")

    if (flg >> 3) & 1 == 1:  # FNAME
        unimplemented("FNAME")

    if (flg >> 4) & 1 == 1:  # FCOMMENT
        unimplemented("FCOMMENT")

    if (flg >> 1) & 1 == 1:  # FHCRC
        unimplemented("FHCRC")

    # Invoke deflate here
    let decoder = new_deflate_decoder(reader)
    decoder.deflate()
    let decompressed = decoder.m_output.to_bytes()

    let crc32 = reader.read_u32_le()
    let isize = reader.read_u32_le()
    assert(condition: isize == decompressed.len(), message: "Invalid length: {isize} != {decompressed.len()}")
    let crc32_check = calc_crc32(data: decompressed)
    print("isize = {isize}, crc32 = {crc32}, crc32_check = {crc32_check}")
    assert(condition: crc32_check == crc32, message: "CRC error: {crc32} != {crc32_check}")
    return decompressed

fn calc_crc32(data: Bytes) -> int:
    # Create table:
    let crc_table = [0 : 256]
    let n = 0
    while n < 256:
        let c = n
        let k = 0
        while k < 8:
            if (c & 1) == 1:
                c = 0xedb88320 ^ (c >> 1)
            else:
                c = c >> 1
            k += 1
        crc_table[n] = c
        n += 1

    # Calculate CRC:
    let crc = 0
    crc = crc ^ 0xffffffff
    for b in data:
        crc = crc_table[(crc ^ b) & 0xff] ^ (crc >> 8)
    crc = crc ^ 0xffffffff

    return crc

