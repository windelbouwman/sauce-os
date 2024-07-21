
# PNG read / write routines
# See RFC 2083

from std import print
from utils import unimplemented, panic, assert, log_error, log_warning, log_debug
from math import abs, modulo
from bytes import Bytes, ByteReader, bytes_from_ascii, bytes_from_hex_text, ByteArray, bytes_to_ascii
from gzip import calc_crc32, zlib_decompress
from deflate import new_deflate_decoder
from qoi import read_whole_file_as_bytes
from image import Image, new_image, Pixel

fn read_png(filename: str) -> Image:
    log_debug("Loading PNG from {filename}")
    let data = read_whole_file_as_bytes(filename)
    let reader = data.into_reader()
    let decoder = PngDecoder(m_byte_reader: reader)
    return decoder.read_image()

class PngDecoder:
    var m_byte_reader: ByteReader

    fn read_image() -> Image:
        let signature = read_bytes(8)
        # let expected_signature = bytes_from_hex_text(text: "aa")
        # assert(condition: signature == 1, message: "Invalid signature")

        let type_ihdr = chunk_type_code(name: "IHDR")
        let type_idat = chunk_type_code(name: "IDAT")
        let type_iend = chunk_type_code(name: "IEND")
        let image = new_image(width: 1, height: 1)
        
        # let type_gama = chunk_type_code(name: "gAMA")
        # let type_gama = chunk_type_code(name: "sRGB")
        loop:
            let chunk = read_chunk()
            if chunk.chunk_type == type_ihdr:
                log_debug("IHDR chunk")
                let r = chunk.data.into_reader()
                let width = r.read_u32_be()
                let height = r.read_u32_be()
                image = new_image(width, height)

                let bitdepth = r.read_byte()
                let colortype = r.read_byte()
                let compression = r.read_byte()
                let filter_method = r.read_byte()
                let interlace_method = r.read_byte()
                log_debug("width={width} height={height} bitdepth={bitdepth} colortype={colortype}")
                log_debug("compression={compression} filter_method={filter_method} interlace_method={interlace_method}")
                assert(condition: bitdepth == 8, message: "Only support 8 bits depth")
                # color types:
                # 0 = grayscale
                # 2 = rgb
                # 3 = indexed
                # 4 = grayscal and alpha
                # 6 = rgb + alpha
                assert(condition: colortype == 2, message: "color type must be rgb")

                # compression type 0 --> zlib deflate format
                assert(condition: compression == 0, message: "compression must be 0")

                # Filter method 0, means 5 pre defined filter types
                assert(condition: filter_method == 0, message: "filter must be 0")
                assert(condition: interlace_method == 0, message: "Only support no interlace")

            elif chunk.chunk_type == type_idat:
                log_debug("IDAT chunk")

                # Decompress data:
                let data2 = zlib_decompress(data: chunk.data)
                log_debug("Decompressed {data2.len()} bytes")
                let expected_data_size = (image.width * 3 + 1) * image.height
                assert(condition: data2.len() == expected_data_size, message: "PNG data size mismatch, expected {expected_data_size}, but got {data2.len()}")

                let scanline = 0
                let index = 0
                let alpha = 0xFF
                let zero_pixel = Pixel(red: 0, green: 0, blue: 0, alpha: 0)
                while scanline < image.height:
                    let filter_type = data2.get(index)
                    index += 1

                    let x = 0
                    while x < image.width:

                        let red = data2.get(index)
                        index += 1
                        let green = data2.get(index)
                        index += 1
                        let blue = data2.get(index)
                        index += 1

                        # filter type:
                        # 0 = None -> no delta
                        # 1 = Sub -> diff to pixel to the left
                        # 2 = Up -> diff to pixel up
                        # 3 = Average
                        # 4 = Paeth
                        if filter_type == 4:
                            let left_pixel = zero_pixel
                            if x > 0:
                                left_pixel = image.pixels.get(index: scanline * image.width + x - 1)
                            let up_pixel = zero_pixel
                            if scanline > 0:
                                up_pixel = image.pixels.get(index: (scanline - 1) * image.width + x)
                            let left_up_pixel = zero_pixel
                            if (x > 0) and (scanline > 0):
                                left_up_pixel = image.pixels.get(index: (scanline - 1) * image.width + x - 1)
                            red = modulo(value: red + paeth_predictor(a: left_pixel.red, b: up_pixel.red, c: left_up_pixel.red), divisor: 256)
                            green = modulo(value: green + paeth_predictor(a: left_pixel.green, b: up_pixel.green, c: left_up_pixel.green), divisor: 256)
                            blue = modulo(value: blue + paeth_predictor(a: left_pixel.blue, b: up_pixel.blue, c: left_up_pixel.blue), divisor: 256)
                        else:
                            unimplemented("Filter type: {filter_type}")
                        
                        # Push pixel:
                        let pixel = Pixel(red, green, blue, alpha)
                        image.pixels.append(pixel)
                        x += 1
                    scanline += 1

            elif chunk.chunk_type == type_iend:
                log_debug("IEND chunk")
                break
            else:
                let type_data = ByteArray()
                type_data.pack_u32_be(chunk.chunk_type)
                log_warning("Unsupported chunk type: {bytes_to_ascii(data: type_data.to_bytes())}")
        return image
    
    fn read_chunk() -> Chunk:
        let chunk_length = read_u32_be()
        let chunk_type = read_u32_be()
        let data = read_bytes(chunk_length)
        let crc_data = ByteArray()
        crc_data.pack_u32_be(chunk_type)
        crc_data.extend(data)
        let chunk_crc = read_u32_be()
        # check crc:
        let crc = calc_crc32(data: crc_data.to_bytes())
        assert(condition: crc == chunk_crc, message: "CRC mismatch: {crc} != {chunk_crc}")
        return Chunk(chunk_type, data)

    fn read_bytes(size?: int) -> Bytes:
        return m_byte_reader.read_bytes(size)

    fn read_u32_be() -> int:
        return m_byte_reader.read_u32_be()

fn paeth_predictor(a: int, b: int, c: int) -> int:
    let p = a + b - c
    let pa = abs(p - a)
    let pb = abs(p - b)
    let pc = abs(p - c)
    if (pa <= pb) and (pa <= pc):
        return a
    elif pb <= pc:
        return b
    else:
        return c

struct Chunk:
    chunk_type: int
    data: Bytes

fn chunk_type_code(name: str) -> int:
    let reader = bytes_from_ascii(text: name).into_reader()
    return reader.read_u32_be()
