
from vectype import Vector, new_vector_of_size

pub fn new_image(width: int, height: int, mode: ColorMode) -> Image:
	let bytes_per_pixel = case mode:
		GrayScale:
			1
		GrayScaleAlpha:
			2
		Color:
			3
		ColorAlpha:
			4
	let data: Vector[int] = new_vector_of_size(size: width * height * bytes_per_pixel, default: 0)
	Image:
		width
		height
		mode
		bytes_per_pixel
		data

pub fn new_empty_image() -> Image:
	new_image(width: 1, height: 1, mode: ColorMode.GrayScale())

pub fn new_black_image(width: int, height: int) -> Image:
	new_image(width, height, mode: ColorMode.ColorAlpha())

pub enum ColorMode:
	GrayScale
	GrayScaleAlpha
	Color
	ColorAlpha

pub class Image:
	pub var width: int
	pub var height: int
	pub var mode: ColorMode
	var bytes_per_pixel: int
	pub var data: Vector[int]

	pub fn get_pixel(x: int, y: int, pixel: Pixel):
		""" Get color and store in given pixel """
		let index = (y * width + x) * bytes_per_pixel
		case mode:
			GrayScale:
				pixel.green = data.get(index)
			GrayScaleAlpha:
				pixel.green = data.get(index)
				pixel.alpha = data.get(index: index + 1)
			Color:
				pixel.red = data.get(index)
				pixel.green = data.get(index: index + 1)
				pixel.blue = data.get(index: index + 2)
			ColorAlpha:
				pixel.red = data.get(index)
				pixel.green = data.get(index: index + 1)
				pixel.blue = data.get(index: index + 2)
				pixel.alpha = data.get(index: index + 3)

	pub fn set_pixel(x: int, y: int, pixel: Pixel):
		""" Set given pixel to a certain color """
		let index = (y * width + x) * bytes_per_pixel
		case mode:
			GrayScale:
				data.set(index, value: pixel.green)
			GrayScaleAlpha:
				data.set(index, value: pixel.green)
				data.set(index: index + 1, value: pixel.alpha)
			Color:
				data.set(index, value: pixel.red)
				data.set(index: index + 1, value: pixel.green)
				data.set(index: index + 2, value: pixel.blue)
			ColorAlpha:
				data.set(index, value: pixel.red)
				data.set(index: index + 1, value: pixel.green)
				data.set(index: index + 2, value: pixel.blue)
				data.set(index: index + 3, value: pixel.alpha)

pub struct Pixel:
	red: int
	green: int
	blue: int
	alpha: int

pub fn new_pixel() -> Pixel:
	Pixel(red: 0, green: 0, blue: 0, alpha: 0)

pub fn copy_pixel(dst: Pixel, src: Pixel):
	dst.red = src.red
	dst.green = src.green
	dst.blue = src.blue
	dst.alpha = src.alpha
