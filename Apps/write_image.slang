module main
"""Demo of saving images"""

from std import get_n_args, get_arg, print
from logging import set_log_level
from utils import panic
from optiontype import Option, option_unwrap
from fs import Path, new_path
from image import Image
from pbm import write_pbm
from png import read_png_from_file, write_png_to_file
from qoi import read_qoi_from_file, write_qoi_to_file
from gif import read_gif_from_file
from jpeg import read_jpg_from_file

fn load_image(path: Path) -> Image:
	# Load image from file
	let extension = path.get_extension()
	if extension == "png":
		read_png_from_file(path)
	elif extension == "qoi":
		read_qoi_from_file(path)
	elif extension == "gif":
		read_gif_from_file(path).first()
	elif extension == "jpg":
		read_jpg_from_file(path)
	else:
		panic("Unsupported image extension for load_image: {extension}")

fn save_image(image: Image, path: Path):
	let extension = path.get_extension()
	if extension == "ppm":
		write_pbm(image, path)
	elif extension == "qoi":
		write_qoi_to_file(image, path)
	elif extension == "png":
		write_png_to_file(image, path)
	else:
		panic("Unsupported image extension for save_image: {extension}")

fn print_usage():
	print("Usage:")
	print("   CMD> write_image.exe input_image_filename output_image_filename")

pub fn main() -> int:
	# Argument processing
	let n = get_n_args()
	var i = 0
	var log_level = 0
	var parse_state = 0
	var input_image: Option[Path] = Option.None()
	var output_image: Option[Path] = Option.None()
	while i < n:
		let argument = get_arg(arg: i)
		if argument == "-h":
			print_usage()
			return 0
		elif argument == "-v":
			log_level += 1
		else:
			if parse_state == 0:
				input_image = Option.Some(new_path(filename: argument))
				parse_state = 1
			elif parse_state == 1:
				output_image = Option.Some(new_path(filename: argument))
				parse_state = 2
			else:
				print("Too many arguments")
				return 1
		i += 1

	if parse_state == 0:
		print_usage()
		return 1

	set_log_level(level: log_level)
	let image = load_image(path: option_unwrap(input_image))
	case output_image:
		Some(output_path):
			save_image(image, path: output_path)
		None:
			pass

	return 0
