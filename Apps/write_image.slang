
# Demo of saving images

from utils import set_log_level
from image import Image, new_image
from pbm import write_pbm
from png import read_png
from qoi import read_qoi, write_qoi


fn main() -> int:
    set_log_level(level: 2)
    # let image = new_image()
    # let image = read_qoi(filename: "foo.qoi")
    # let image = read_png(filename: "kodim23.png")
    let image = read_png(filename: "PNG-Gradient.png")
    write_pbm(image, filename: "bar.ppm")
    # write_qoi(image, filename: "bar.qoi")
    return 0
