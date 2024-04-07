
# PNG read / write routines

from std import print
from utils import unimplemented, panic, assert
from bytes import Bytes, ByteReader, bytes_from_ascii, bytes_from_hex_text
from gzip import calc_crc32
from image import Image

fn read_png(data?: Bytes):
    let reader = data.into_reader()
    let decoder = PngDecoder(m_byte_reader: reader)

class PngDecoder:
    var m_byte_reader: ByteReader

    fn read_image() -> Image:
        let signature = read_bytes(8)
        # let expected_signature = bytes_from_hex_text(text: "aa")
        # assert(condition: signature == 1, message: "Invalid signature")

        let type_ihdr = chunk_type_code(name: "IHDR")
        let type_idat = chunk_type_code(name: "IDAT")
        let type_iend = chunk_type_code(name: "IEND")
        loop:
            let chunk = read_chunk()
            if chunk.chunk_type == type_ihdr:
                print("IHDR")
            elif chunk.chunk_type == type_idat:
                print("IDAT")
            elif chunk.chunk_type == type_iend:
                print("IEND")
                break
            else:
                panic("Unsupported chunk type: {chunk.chunk_type}")
        unimplemented("read_image")
    
    fn read_chunk() -> Chunk:
        let chunk_length = read_u32()
        let chunk_type = read_u32()
        let data = read_bytes(chunk_length)
        let chunk_crc = read_u32()
        # check crc:
        let crc = calc_crc32(data)
        assert(condition: crc == chunk_crc, message: "CRC mismatch: {crc} != {chunk_crc}")
        return Chunk(chunk_type, data)

    fn read_bytes(n?: int) -> Bytes:
        unimplemented("read_bytes")

    fn read_u32() -> int:
        return m_byte_reader.read_u32_be()


struct Chunk:
    chunk_type: int
    data: Bytes

fn chunk_type_code(name: str) -> int:
    let reader = bytes_from_ascii(text: name).into_reader()
    return reader.read_u32_be()
