
# 
# encoder / decoder for the QOI (quite ok image) format.
#
# See also: https://qoiformat.org/
# https://qoiformat.org/qoi-specification.pdf

import std
from utils import panic, log_info, assert
from bytes import Bytes, ByteReader, ByteArray, bytes_to_ascii, bytes_from_ascii
from vectype import Vector, new_vector
from math import modulo
from image import Image, new_image, Pixel, new_pixel

pub fn read_whole_file_as_bytes(filename: str) -> Bytes:
    # Helper to read in a whole file into a bytes object in memory
    let handle = std.file_open(filename, mode: "rb")
    let ba = ByteArray()
    let buffer: [uint8] = [200 : uint8]
    loop:
        let res = std.file_read_n_bytes(handle, buffer, bufsize: 200)
        if res > 0:
            let i = 0
            while i < res:
                ba.append(int(buffer[i]))
                i += 1
        else:
            break
    std.file_close(handle)

    ba.to_bytes()

pub fn write_bytes_to_file(filename: str, data: Bytes):
    let handle = std.file_open(filename, mode: "wb")
    let buffer: [uint8] = [200 : uint8]
    let i = 0
    let j = 0
    while i < data.len():
        buffer[j] = uint8(data[i])
        j += 1
        if j == 200:
            let x = std.file_write_n_bytes(handle, buffer, bufsize: j)
            assert(condition: x == j, message: "file_write_n_bytes failed")
            j = 0
        i += 1

    if j > 0:
        let x = std.file_write_n_bytes(handle, buffer, bufsize: j)
        assert(condition: x == j, message: "file_write_n_bytes failed")

    std.file_close(handle)

# TODO: support constants:
# QOI_OP_RGB = 0b1111_1110
# QOI_OP_RGBA = 0b1111_1111

pub fn read_qoi_from_file(filename: str) -> Image:
    let data = read_whole_file_as_bytes(filename)
    let reader = QoiReader(m_reader: data.into_reader())
    reader.read_image()

pub fn write_qoi_to_file(image: Image, filename: str):
    # Write image as QOI file.
    let writer = QoiWriter()
    let data = writer.write(image)
    write_bytes_to_file(filename, data)

class QoiReader:
    var m_reader: ByteReader
    var m_array: Vector[Pixel] = new_vector()
    var m_pixels: Vector[Pixel] = new_vector()

    pub fn read_image() -> Image:
        # let f = std.open_binary(filename)
        let magic = bytes_to_ascii(data: read_bytes(4))
        assert(condition: magic == "qoif", message: "Not a QOI image")

        # let magic = header[0,4]  # TODO: support [0:4]?
        let width = m_reader.read_u32_be()
        let height = m_reader.read_u32_be()
        let channels = read_byte()
        let colorspace = read_byte()
        log_info("Header: magic={magic} width={width} height={height}")

        let image = new_image(width, height)

        let i = 0
        while i < 64:
            m_array.append(new_pixel())
            i += 1
        
        let r = 0
        let g = 0
        let b = 0
        let a = 0xFF

        let dr = 0
        let dg = 0
        let db = 0
        while m_pixels.len() < width * height:
            let tag8 = read_byte()
            switch tag8:
                0b11111110:   # QOI_OP_RGB
                    # TODO: support many unpack: r, g, b = read(3)
                    r = read_byte()
                    g = read_byte()
                    b = read_byte()
                    put_pixel(r, g, b, a)
                0b11111111:  # QOI_OP_RGBA
                    r = read_byte()
                    g = read_byte()
                    b = read_byte()
                    a = read_byte()
                    put_pixel(r, g, b, a)
            else:
                # Check top 2 bits:
                let tag2 = tag8 >> 6
                switch tag2:
                    0b00:  # QOI_OP_INDEX
                        let index = tag8 & 0x3F
                        let pixel = m_array[index]
                        r = pixel.red
                        g = pixel.green
                        b = pixel.blue
                        a = pixel.alpha
                        put_pixel(r, g, b, a)
                    0b01: # QOI_OP_DIFF
                        dr = ((tag8 >> 4) & 3) - 2
                        dg = ((tag8 >> 2) & 3) - 2
                        db = (tag8 & 3) - 2
                        r = wrap8(r + dr)
                        g = wrap8(g + dg)
                        b = wrap8(b + db)
                        put_pixel(r, g, b, a)
                    0b10:  # QOI_OP_LUMA
                        dg = (tag8 & 0x3F) - 32
                        let x = read_byte()
                        dr = (((x >> 4) & 0xF) - 8) + dg
                        db = ((x & 0xF) - 8) + dg
                        r = wrap8(r + dr)
                        g = wrap8(g + dg)
                        b = wrap8(b + db)
                        put_pixel(r, g, b, a)
                    0b11:  # QOI_OP_RUN
                        let length = (tag8 & 0x3F) + 1
                        let i = 0
                        while i < length:
                            put_pixel(r, g, b, a)
                            i += 1
                else:
                    panic("read_image: Invalid opcode: {tag2}")
                # std.print("Pixel: {r} {g} {b} {a}")
        image.pixels = m_pixels
        image
    
    fn put_pixel(r: int, g: int, b: int, a: int):
        # std.print("Pixel: {r} {g} {b} {a}")
        let index = modulo(value: r * 3 + g * 5 + b * 7 + a * 11, divisor: 64)
        let pixel = Pixel(red: r, green: g, blue: b, alpha: a)
        m_array.set(index, value: pixel)
        m_pixels.append(pixel)

    fn read_bytes(size?: int) -> Bytes:
        m_reader.read_bytes(size)
    
    fn read_byte() -> int:
        m_reader.read_byte()

fn wrap8(value?: int) -> int:
    # Implement 8 bit wrapping
    while value < 0:
        value += 256
    while value > 255:
        value -= 256
    value

class QoiWriter:
    var m_writer: ByteArray = ByteArray()

    pub fn write(image: Image) -> Bytes:
        let magic = bytes_from_ascii(text: "qoif")
        m_writer.extend(magic)

        m_writer.pack_u32_be(image.width)
        m_writer.pack_u32_be(image.height)
        m_writer.append(3)  # channels, 3 = RGB
        m_writer.append(0)  # colorspace

        # TODO: we can encode image more efficiently.
        # for now, store all pixels seperately
        let i = 0
        while i < image.width * image.height:
            write_byte(0b11111110) # QOI_OP_RGB
            write_byte(image.pixels[i].red)
            write_byte(image.pixels[i].green)
            write_byte(image.pixels[i].blue)
            i += 1
        m_writer.to_bytes()

    fn write_byte(value?: int):
        m_writer.append(value)
