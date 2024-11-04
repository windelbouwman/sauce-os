import std

fn main() -> int:
    # """ Print a mandelbrot fractal to the console """
    let w = 75
    let h = 24
    let y = 0
    while y < h:
        let x = 0
        let line = ""
        while x < w:
            let Zr = 0.0
            let Zi = 0.0
            let Tr: float = 0
            let Ti = 0.0
            let Cr = 2.0 * x / w - 1.5
            let Ci = 2.0 * (float(y) / h) - 1.0

            let i = 0
            while i < 50 and Tr + Ti <= 4.0:
                Zi = 2.0 * Zr * Zi + Ci
                Zr = Tr - Ti + Cr
                Tr = Zr * Zr
                Ti = Zi * Zi
                i = i + 1

            if Tr + Ti <= 4.0:
                # std.putc('*')
                line = line + "*"
            else:
                line = line + " "
                # std.putc(' ')

            x += 1

        # std.putc('\n')
        std.print(line)
        y += 1

    0  
