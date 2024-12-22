
from vectype import Vector, new_vector

pub fn new_image(width: int, height: int) -> Image:
    let pixels: Vector[Pixel] = new_vector()
    Image:
        width
        height
        pixels

pub class Image:
    var width: int
    var height: int
    var pixels: Vector[Pixel]

    pub fn get_pixel(x: int, y: int) -> Pixel:
        let index = y * width + x
        let pixel = pixels[index]
        pixel
    
    pub fn set_pixel(x: int, y: int, red: int, green: int, blue: int, alpha: int):
        let pixel = get_pixel(x, y)
        pixel.red = red
        pixel.green = green
        pixel.blue = blue
        pixel.alpha = alpha

    pub fn add_pixel(red: int, green: int, blue: int, alpha: int):
        pixels.append(Pixel(red, green, blue, alpha))


pub struct Pixel:
    red: int
    green: int
    blue: int
    alpha: int

pub fn new_pixel() -> Pixel:
    Pixel(red: 0, green: 0, blue: 0, alpha: 0)
