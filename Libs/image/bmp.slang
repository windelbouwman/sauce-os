module image.bmp
# TODO
from base.logging import log_debug
from image import Image
from base.fs import Path

pub fn write_bmp_to_file(image: Image, filename: Path):
	log_debug("Writing BMP image to {filename}")
