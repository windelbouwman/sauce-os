
# Demo of saving images

from std import get_n_args, get_arg, print
from utils import set_log_level, panic
from strlib import split_string
from image import Image
from pbm import write_pbm
from png import read_png_from_file, write_png_to_file
from qoi import read_qoi_from_file, write_qoi_to_file
from gif import read_gif_from_file
from jpeg import read_jpg_from_file

fn load_image(filename: str) -> Image:
	# Load image from file
	let extension = get_extension(filename)
	if extension == "png":
		read_png_from_file(filename)
	elif extension == "qoi":
		read_qoi_from_file(filename)
	elif extension == "gif":
		read_gif_from_file(filename).first()
	elif extension == "jpg":
		read_jpg_from_file(filename)
	else:
		panic("Unsupported image extension for load_image: {extension}")

fn save_image(image: Image, filename: str):
	let extension = get_extension(filename)
	if extension == "ppm":
		write_pbm(image, filename)
	elif extension == "qoi":
		write_qoi_to_file(image, filename)
	elif extension == "png":
		write_png_to_file(image, filename)
	else:
		panic("Unsupported image extension for save_image: {extension}")

fn get_extension(filename: str) -> str:
	split_string(text: filename, sep: '.').last()

fn print_usage():
	print("Usage:")
	print("   CMD> write_image.exe input_image_filename output_image_filename")

pub fn main() -> int:
	# Argument processing
	let n = get_n_args()
	var i = 0
	var log_level = 0
	var parse_state = 0
	var input_image: str = ""
	var output_image: str = ""
	while i < n:
		let argument = get_arg(arg: i)
		if argument == "-h":
			print_usage()
			return 0
		elif argument == "-v":
			log_level += 1
		else:
			if parse_state == 0:
				input_image = argument
				parse_state = 1
			elif parse_state == 1:
				output_image = argument
				parse_state = 2
			else:
				print("Too many arguments")
				return 1
		i += 1

	if parse_state != 2:
		print_usage()
		return 1

	set_log_level(level: log_level)
	let image = load_image(filename: input_image)
	save_image(image, filename: output_image)

	return 0
