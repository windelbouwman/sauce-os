
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
from logging import log_info
from utils import unimplemented
from image import Image, new_pixel

pub fn write_pbm(image: Image, filename: str):
	log_info("Writing image to {filename} in PPM format")
	let handle = file_open(filename, mode: "w")
	case image.mode:
		GrayScale:
			file_writeln(handle, line: "P2")
		GrayScaleAlpha:
			unimplemented("pbm: GrayScaleAlpha")
		Color:
			file_writeln(handle, line: "P3")
		ColorAlpha:
			unimplemented("pbm: ColorAlpha")
	file_writeln(handle, line: "{image.width} {image.height}")
	file_writeln(handle, line: "255")

	let pixel = new_pixel()
	var y = 0
	while y < image.height:
		var x = 0
		while x < image.width:
			image.get_pixel(x, y, pixel)
			case image.mode:
				GrayScale:
					file_writeln(handle, line: "{pixel.green}")
				GrayScaleAlpha:
					unimplemented("pbm: GrayScaleAlpha")
				Color:
					file_writeln(handle, line: "{pixel.red} {pixel.green} {pixel.blue}")
				ColorAlpha:
					unimplemented("pbm: ColorAlpha")
			x += 1
		y += 1
	file_close(handle)
