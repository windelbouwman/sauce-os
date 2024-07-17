
# Demo of saving images

from image import Image, new_image
from pbm import write_pbm
from png import read_png
from qoi import read_qoi, write_qoi


fn main() -> int:
    # let image = new_image()
    let image = read_qoi(filename: "foo.qoi")
    #let image = read_png(data)
    # write_pbm(image)
    write_qoi(image, filename: "bar.qoi")
    return 0
