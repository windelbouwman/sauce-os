
"
encoder / decoder for the QOI (quite ok image) format.

See also: https://qoiformat.org/

"

import std

# TODO: support constants:
# QOI_OP_RGB = 0b1111_1110
# QOI_OP_RGBA = 0b1111_1111

fn read_qoi(filename: str):
    let f = std::open_binary(filename)
    let header = read(14)

    let magic = header[0,4]  # TODO: support [0:4]?
    let width = unpack_u32_be(header[4,8])
    let height = unpack_u32_be(header[8,12])
    let channels = header[12]
    let colorspace = header[13]

    let history = array(64)
    let r=0
    let g=0
    let b=0
    let a = 0xFF
    loop:
        tag8 = read(1)
        switch tag8:
            0b1111_1110:   # QOI_OP_RGB
                # TODO: support many unpack: r, g, b = read(3)
                r = read(1)
                g = read(1)
                b = read(1)
            0b1111_1111:  # QOI_OP_RGBA
                r = read(1)
                g = read(1)
                b = read(1)
                a = read(1)
            else:
                # Check top 2 bits:
                tag2 = tag8 >> 6
                switch tag2:
                    0b00:  # QOI_OP_INDEX
                        index = tag8 & 0x3F

                    0b01: # QOI_OP_DIFF
                        dr = (tag8 >> 4) & 3
                        dg = (tag8 >> 2) & 3
                        db = tag8 & 3
                        # TODO: support += !
                        r = r + dr - 2
                        g = g + dg - 2
                        b = b + db - 2
                    0b10:  # QOI_OP_LUMA
                        pass
                    0b11:  # QOI_OP_RUN
                        length = tag8 & 0x3F
                    else:
                        pass
                    


fn write_qoi(filename: str):
    pass
