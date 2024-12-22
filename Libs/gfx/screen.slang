
from utils import assert
from math import abs
from image import Image, new_image, Pixel
from png import write_png_to_file

pub fn new_screen(width: int, height: int) -> Screen:
    assert(condition: width > 0, message: "Width must be larger than 0")
    assert(condition: height > 0, message: "Height must be larger than 0")
    let image = new_image(width, height)
    let i = 0
    while i < width * height:
        image.add_pixel(red: 1, green: 1, blue: 1, alpha: 1)
        i += 1
    Screen(m_width: width, m_height: height, m_image: image)

pub class Screen:
    """ A bitmap painter.
    """
    var m_width: int
    var m_height: int
    var m_image: Image
    var m_color: Pixel = Pixel(red: 0, green: 0, blue: 200, alpha: 255)

    pub fn set_color(red: int, green: int, blue: int):
        m_color.red = red
        m_color.green = green
        m_color.blue = blue

    pub fn clear():
        """ Set entire screen to color. """
        let y = 0
        while y < m_height:
            let x = 0
            while x < m_width:
                put_pixel(x, y)
                x += 1
            y += 1

    pub fn draw_line(x1: int, y1: int, x2: int, y2: int):
        """ Draw a line from x1,y1 to x2,y2 in the current color.
        
        Use Bresenham's algorithm

        See also: https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
        """
        # Check for straight lines first:
        if x1 == x2:
            draw_vertical_line(x: x1, y1, y2)
        elif y1 == y2:
            draw_horizontal_line(y: y1, x1, x2)
        else:
            # Not a straight line
            if abs(x2 - x1) > abs(y2 - y1):
                if x2 < x1:
                    # Swap p1 and p2
                    let tmp = x1
                    x1 = x2
                    x2 = tmp
                    tmp = y1
                    y1 = y2
                    y2 = tmp
                
                let dx = x2 - x1
                let dy = y2 - y1

                let sy = 1
                if dy < 0:
                    dy = -dy
                    sy = -1
                let x = x1
                let y = y1

                let D = 2 * dy - dx

                while x <= x2:
                    put_pixel(x, y)
                    if D > 0:
                        y += sy
                        D = D - 2 * dx
                    D = D + 2 * dy
                    x += 1
            else:
                if y2 < y1:
                    # Swap p1 and p2
                    let tmp = x1
                    x1 = x2
                    x2 = tmp
                    tmp = y1
                    y1 = y2
                    y2 = tmp

                let dx = x2 - x1
                let dy = y2 - y1

                let sx = 1
                if dx < 0:
                    dx = -dx
                    sx = -1

                let x = x1
                let y = y1
                let D = 2 * dx - dy

                while y <= y2:
                    put_pixel(x, y)
                    if D > 0:
                        x += sx
                        D = D - 2 * dy
                    D = D + 2 * dx
                    y += 1

    fn draw_vertical_line(x: int, y1: int, y2: int):
        """ Vertical line """
        let y = y1
        if y2 < y:
            y = y2
            y2 = y1
        while y <= y2:
            put_pixel(x, y)
            y += 1

    fn draw_horizontal_line(y: int, x1: int, x2: int):
        """ Horizontal line """
        let x = x1
        if x2 < x1:
            x = x2
            x2 = x1
        while x <= x2:
            put_pixel(x, y)
            x += 1

    pub fn put_pixel(x: int, y: int):
        m_image.set_pixel(x, y, red: m_color.red, green: m_color.green, blue: m_color.blue, alpha: 255)

    pub fn save_png(filename: str):
        write_png_to_file(image: m_image, filename)
