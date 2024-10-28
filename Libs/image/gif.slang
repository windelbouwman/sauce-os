
# GIF fileformat
from utils import unimplemented, panic, assert, log_info, log_debug, log_trace
from datatypes import List
from bytes import Bytes, new_bytes, ByteReader, ByteArray
from bytes import bytes_to_ascii, fill_bytes
from vectype import Vector, new_vector
from image import Image, new_image
from qoi import read_whole_file_as_bytes


fn read_gif_from_file(filename: str) -> List[Image]:
    log_debug("Loading GIF from {filename}")
    let data = read_whole_file_as_bytes(filename)
    read_gif_from_bytes(data)

fn read_gif_from_bytes(data: Bytes) -> List[Image]:
    let reader = data.into_reader()
    let gif_reader = GifReader(m_byte_reader: reader)
    gif_reader.read()

enum Version:
    GIF87a
    GIF89a

struct Color:
    r: int
    g: int
    b: int

class GifReader:
    var m_byte_reader: ByteReader

    var m_version: Version = Version.GIF89a()
    var m_width: int = 0
    var m_height: int = 0
    var m_global_color_table_present: bool = false
    var m_palette: Vector[Color] = new_vector()
    var m_images: List[Image] = List()

    fn read() -> List[Image]:
        read_header()
        read_logical_screen_descriptor()
        if m_global_color_table_present:
            m_palette = read_color_table(size: 256)

        # Read blocks
        loop:
            let block_type = read_u8()
            if block_type == 0x2C:  # Image descriptor
                read_image_descriptor()
            elif block_type == 0x21:  # Extension
                read_extension()
            elif block_type == 0x3B:  # Trailer
                break
            else:
                unimplemented("Block type: {block_type}")

        m_images
    
    fn read_extension():
        let label = read_u8()
        if label == 0xF9: # Graphic control
            log_trace("Graphic control extension")
            let size = read_u8()
            assert(condition: size == 4, message: "Graphic control extension must be 4 bytes")
            let flags = read_u8()
            let delay_time = read_u16()
            let transparent_color = read_u8()
            let terminator = read_u8()
            assert(condition: terminator == 0, message: "Must be terminator")
            log_trace("delay time: {delay_time}")
        elif label == 0xFF: # Application extension
            log_trace("Application extension")
            loop:
                let block = read_block()
                if block.len() == 0:
                    break
        else:
            unimplemented("Extension: {label}")

    fn read_image_descriptor():
        let pos_left = read_u16()
        let pos_top = read_u16()
        let width = read_u16()
        let height = read_u16()
        log_trace("Image descriptor: Width={width} Height={height}")
        let flags = read_u8()
        let local_color_table_present: bool = (flags >> 7) & 1 == 1
        let interlace_flag: bool = (flags >> 6) & 1 == 1
        let sort_flag: bool = (flags >> 5) & 1 == 1
        let size_of_local_color_table = 1 << ((flags & 7) + 1)
        assert(condition: not interlace_flag, message: "interlace not supported")

        if local_color_table_present:
            m_palette = read_color_table(size: size_of_local_color_table)

        # image data
        let lzw_minumum_code_size = read_u8()
        let lzw_data = ByteArray()
        loop:
            let block = read_block()
            if block.len() == 0:
                break
            else:
                lzw_data.extend(data: block)
        let uncompressed = lzw_decode(data: lzw_data.to_bytes())

        assert(condition: uncompressed.len() == width * height, message: "width and height do not match decompressed data")
        let image = new_image(width, height)
        for value in uncompressed:
            let color = m_palette[value]
            image.add_pixel(red: color.r, green: color.g, blue: color.b, alpha: 255)

        m_images.append(image)

    fn read_block() -> Bytes:
        let size = read_u8()
        m_byte_reader.read_bytes(size)

    fn read_header():
        let header = read_text(size: 6)
        if header == "GIF89a":
            m_version = Version.GIF89a()
        elif header == "GIF87a":
            m_version = Version.GIF87a()
        else:
            panic("Invalid version: {header}")
    
    fn read_logical_screen_descriptor():
        m_width = read_u16()
        m_height = read_u16()
        let packed = read_u8()
        let size_of_global_color_table = packed & 0x7
        assert(condition: size_of_global_color_table == 7, message: "Only supports 8 bits per pixel")
        let color_resolution = (packed >> 4) & 0x7
        assert(condition: color_resolution == 7, message: "Only supports 8 bits per primary color")
        m_global_color_table_present = (packed >> 7) == 1
        let background_color = read_u8()
        let aspect_ration = read_u8()
        log_trace("Logical screen descriptor: width={m_width} height={m_height}")
    
    fn read_color_table(size: int) -> Vector[Color]:
        log_trace("Reading pallete with {size} colors")
        let palette: Vector[Color] = new_vector()
        let index = 0
        while index < size:
            let r = read_u8()
            let g = read_u8()
            let b = read_u8()
            palette.append(Color(r, g, b))
            index += 1
        palette
    
    fn read_text(size: int) -> str:
        let data = m_byte_reader.read_bytes(size)
        bytes_to_ascii(data)

    fn read_u16() -> int:
        m_byte_reader.read_u16_le()
    
    fn read_u8() -> int:
        m_byte_reader.read_byte()

fn lzw_decode(data: Bytes) -> Bytes:
    """ Decompress LZW encodeded data. """
    let compressed_size = data.len()
    log_debug("LZW decoding {compressed_size} bytes")
    let decoder = LzwDecoder(m_reader: data.into_reader())
    decoder.decode()
    let decompressed = decoder.m_output.to_bytes()
    let decompressed_size = decompressed.len()
    let factor = decompressed_size / compressed_size
    log_debug("Decompressed {decompressed_size} bytes (a factor {factor})")
    decompressed

class LzwDecoder:
    # var m_index: int = 0
    var m_reader: ByteReader
    var m_bitbuf: int = 0
    var m_bitcnt: int = 0
    var m_code_bit_size: int = 9
    var m_table: Vector[Bytes] = new_vector()
    var m_output: ByteArray = ByteArray()

    fn decode():
        let oldcode = 256 # Clear code
        m_code_bit_size = 9
        loop:
            let code = get_next_code()
            if code == 256:  # clear code
                initialize_table()
                code = get_next_code()
                if code == 257:
                    break
                else:
                    emit(m_table[code])
                    oldcode = code
            elif code == 257:  # End of information marker
                break
            else:
                if code < m_table.len():  # code in table
                    emit(m_table[code])
                    add_to_table(m_table[oldcode].concat(other: first_char(m_table[code])))
                    oldcode = code
                else:
                    let outstring = m_table[oldcode].concat(other: first_char(m_table[oldcode]))
                    emit(outstring)
                    add_to_table(outstring)
                    oldcode = code

    fn initialize_table():
        m_table.clear()
        let i = 0
        while i < 256:
            m_table.append(fill_bytes(n: 1, fill: i))
            i += 1
        m_table.append(new_bytes())  # 256 clear code
        m_table.append(new_bytes())  # 257 end of information
        m_code_bit_size = 9

    fn add_to_table(x?: Bytes):
        if m_table.len() < 4095:
            m_table.append(x)
            if m_table.len() == (1 << m_code_bit_size):
                m_code_bit_size += 1

    fn get_next_code() -> int:
        let code = read_bits(m_code_bit_size)
        # log_debug("Code = {code}")
        code

    fn read_byte() -> int:
        m_reader.read_byte()

    fn read_bits(n?: int) -> int:
        let value = m_bitbuf
        while m_bitcnt < n:
            let byte = read_byte()
            value = (byte << m_bitcnt) | value
            m_bitcnt += 8
        m_bitbuf = value >> n
        m_bitcnt -= n
        let mask = ((1 << n) - 1)
        value & mask
    
    fn emit(data?: Bytes):
        m_output.extend(data)

fn first_char(data?: Bytes) -> Bytes:
    fill_bytes(n: 1, fill: data[0])
