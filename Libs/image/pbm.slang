
# """
# See also: https://en.wikipedia.org/wiki/Netpbm#File_formats
#
# PBM:
#     Portable BitMap
#     P1
#     0 = white
#     1 = black
#
# PGM:
#     P2
#     Portable GrayMap
#     0-maxvalue (black to white)
#
# PPM:
#     Portable PixMap
#     P3
#
# """

from std import file_writeln, file_open, file_close
from utils import log_info
from image import Image

pub fn write_pbm(image: Image, filename: str):
    log_info("Writing image to {filename} in PPM format")
    let handle = file_open(filename, mode: "w")
    file_writeln(handle, line: "P3")
    file_writeln(handle, line: "{image.width} {image.height}")
    file_writeln(handle, line: "255")

    let y = 0
    while y < image.height:
        let x = 0
        while x < image.width:
            let pixel = image.get_pixel(x, y)
            file_writeln(handle, line: "{pixel.red} {pixel.green} {pixel.blue}")
            x += 1
        y += 1
    file_close(handle)
