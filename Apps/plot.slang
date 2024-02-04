
# A plotting example program.

import std
from utils import log_info, set_log_level
from strlib import split_lines
from chart import Chart

fn main() -> int:
    set_log_level(level: 2)
    log_info("Plotting curves")
    let c = Chart()
    let line1 = c.new_curve(name: "parabole")
    let line2 = c.new_curve(name: "y = x")
    let line3 = c.new_curve(name: "y = x^3")
    let x = -10.0
    while x < 10.0:
        let y1 = (x * x) / 10.0
        let y2 = x
        let y3 = (x - 4) * x * (x + 4) / 5.0
        line1.add_point(x, y: y1)
        line2.add_point(x, y: y2)
        line3.add_point(x, y: y3)
        x += 0.7

    # c.autoscale()
    # c.zoom_out()
    # c.zoom(factor: 0.1)
    c.to_svg(filename: "data-plot.svg")

    return 0
