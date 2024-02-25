
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

from utils import unimplemented
from image import Image

fn write_pbm(image: Image):

    let y = 0
    while y < image.height:
        let x = 0
        while x < image.width:
            let pixel = image.get_pixel(x, y)
            # print("")
            x += 1
        y += 1

    unimplemented("write_pbm")
