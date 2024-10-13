
from vectype import Vector, new_vector

fn new_image(width: int, height: int) -> Image:
    let pixels: Vector[Pixel] = new_vector()
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
    
    fn set_pixel(x: int, y: int, red: int, green: int, blue: int, alpha: int):
        let pixel = get_pixel(x, y)
        pixel.red = red
        pixel.green = green
        pixel.blue = blue
        pixel.alpha = alpha

    fn add_pixel(red: int, green: int, blue: int, alpha: int):
        pixels.append(Pixel(red, green, blue, alpha))


struct Pixel:
    red: int
    green: int
    blue: int
    alpha: int

fn new_pixel() -> Pixel:
    return Pixel(red: 0, green: 0, blue: 0, alpha: 0)
