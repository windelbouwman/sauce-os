
from vectype import Vector, new_vector

fn new_image(width: int, height: int) -> Image:
    let pixels: Vector[Pixel] = new_vector(default: new_pixel())
    let image = Image:
        width
        height
        pixels
    return image

class Image:
    var width: int
    var height: int
    var pixels: Vector[Pixel]

    fn get_pixel(x: int, y: int) -> Pixel:
        let index = y * width + x
        let pixel = pixels[index]
        return pixel


struct Pixel:
    red: int
    green: int
    blue: int
    alpha: int

fn new_pixel() -> Pixel:
    return Pixel(red: 0, green: 0, blue: 0, alpha: 0)
