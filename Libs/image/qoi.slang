
# 
# encoder / decoder for the QOI (quite ok image) format.
#
# See also: https://qoiformat.org/

import std
from utils import unimplemented
from bytes import Bytes, ByteReader
from image import Image

# TODO: support constants:
# QOI_OP_RGB = 0b1111_1110
# QOI_OP_RGBA = 0b1111_1111

fn read_qoi(filename: str) -> Image:
    let reader = QoiReader()
    return reader.read_image()

fn write_qoi(image: Image, filename: str):
    # Write image as QOI file.
    pass

class QoiReader:
    # var m_reader: ByteReader

    fn read_image() -> Image:
        # let f = std.open_binary(filename)
        let header = read(14)

        # let magic = header[0,4]  # TODO: support [0:4]?
        # let width = unpack_u32_be(header[4,8])
        # let height = unpack_u32_be(header[8,12])
        # let channels = header[12]
        # let colorspace = header[13]

        # let history = array(64)
        let r = 0
        let g = 0
        let b = 0
        let a = 0xFF
        loop:
            let tag8 = read_byte()
            switch tag8:
                0b11111110:   # QOI_OP_RGB
                    # TODO: support many unpack: r, g, b = read(3)
                    r = read_byte()
                    g = read_byte()
                    b = read_byte()
                0b11111111:  # QOI_OP_RGBA
                    r = read_byte()
                    g = read_byte()
                    b = read_byte()
                    a = read_byte()
            else:
                # Check top 2 bits:
                let tag2 = tag8 >> 6
                switch tag2:
                    0b00:  # QOI_OP_INDEX
                        let index = tag8 & 0x3F

                    0b01: # QOI_OP_DIFF
                        let dr = (tag8 >> 4) & 3
                        let dg = (tag8 >> 2) & 3
                        let db = tag8 & 3
                        # TODO: support += !
                        r = r + dr - 2
                        g = g + dg - 2
                        b = b + db - 2
                    0b10:  # QOI_OP_LUMA
                        pass
                    0b11:  # QOI_OP_RUN
                        let length = tag8 & 0x3F
                else:
                    pass

        unimplemented("read_image")

    fn read(size?: int) -> Bytes:
        unimplemented("read")
    
    fn read_byte() -> int:
        unimplemented("read_byte")

# class QoiWriter:

