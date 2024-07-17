
# Functionality to charts and plotting.

from std import float_to_str, float_to_str2
from math import floor, log10, powf, fabs, fmin, fmax
from datatypes import List, Option
from sorting import find_min_value
from utils import log_info, panic, assert
from canvas import Canvas, HorizontalAnchor, VerticalAnchor
from functools import reduce
from shapelib import Point, Path

class Chart:
    var m_x_axis: Axis = Axis()
    var m_y_axis: Axis = Axis()
    var m_curves: List[Curve] = List()
    var m_color_wheel: ColorWheel = ColorWheel()

    fn to_svg(filename: str):
        let c = Canvas()
        let drawer = ChartDrawer(m_chart: this, m_canvas: c)
        drawer.draw()
        c.save_svg(filename)

    fn new_color() -> str:
        return m_color_wheel.get_color()

    fn new_curve(name: str) -> Curve:
        let points: List[DataPoint] = List()
        let color = new_color()
        let c = Curve(points, color)
        m_curves.append(c)
        return c
    
    fn add_curve(name: str, points: List[DataPoint]):
        let color = new_color()
        let c = Curve(points, color)
        m_curves.append(c)

    fn get_data_bounds() -> Option[FRange]:
        # Retrieve bounds of the data in this chart.
        let rects: List[FRange] = List()
        for curve in m_curves:
            case curve.get_data_bounds():
                None:
                    pass
                Some(span):
                    rects.append(span)

        if rects.is_empty():
            return Option.None()
        else:
            let rect = reduce(values: rects, f: containing_rect)
            rect = grow_rect(source: rect, percent: 0.05)
            return Option.Some(rect)

    fn autoscale():
        # adjust axis to view all data!
        log_info("Autoscale")
        case get_data_bounds():
            None:
                pass
            Some(span):
                m_x_axis.lower = span.x_min
                m_x_axis.upper = span.x_max
                m_y_axis.lower = span.y_min
                m_y_axis.upper = span.y_max
    
    fn autoscale_x():
        # Adjust x-axis to fit all data
        log_info("Autoscale-x")
        case get_data_bounds():
            None:
                pass
            Some(span):
                m_x_axis.lower = span.x_min
                m_x_axis.upper = span.x_max

    fn autoscale_y():
        # Adjust y-axis to fit all data
        log_info("Autoscale-y")
        case get_data_bounds():
            None:
                pass
            Some(span):
                m_y_axis.lower = span.y_min
                m_y_axis.upper = span.y_max

    fn zoom(factor: float):
        m_x_axis.scale(factor)
        m_y_axis.scale(factor)

    fn zoom_in():
        zoom(factor: 0.5)

    fn zoom_out():
        zoom(factor: 1.5)

    fn pan_x(delta: float):
        m_x_axis.pan(delta)

    fn pan_y(delta: float):
        m_y_axis.pan(delta)

class Axis:
    var lower: float = -10.0
    var upper: float = 10.0

    fn domain() -> float:
        return upper - lower

    fn scale(factor: float):
        lower = lower * factor
        upper = upper * factor
    
    fn pan(delta: float):
        lower = lower + delta
        upper = upper + delta

class Curve:
    var points: List[DataPoint]
    var color: str

    fn add_point(x: float, y: float):
        points.append(DataPoint(x, y))

    fn get_data_bounds() -> Option[FRange]:
        if points.is_empty():
            return Option.None()
        else:
            let p1 = points.first()
            let x_min = p1.x
            let x_max = x_min
            let y_min = p1.y
            let y_max = y_min
            for point in points:
                if point.x > x_max:
                    x_max = point.x
                if point.x < x_min:
                    x_min = point.x
                if point.y > y_max:
                    y_max = point.y
                if point.y < y_min:
                    y_min = point.y
            return Option.Some(FRange(x_min, x_max, y_min, y_max))

struct DataPoint:
    x: float
    y: float

struct FRange:
    # Bounding rectangle
    x_min: float
    x_max: float
    y_min: float
    y_max: float

fn containing_rect(left: FRange, right: FRange) -> FRange:
    let x_min = fmin(left.x_min, right.x_min)
    let x_max = fmax(left.x_max, right.x_max)
    let y_min = fmin(left.y_min, right.y_min)
    let y_max = fmax(left.y_max, right.y_max)
    return FRange(x_min, x_max, y_min, y_max)

fn grow_rect(source: FRange, percent: float) -> FRange:
    let dx = (source.x_max - source.x_min) * percent
    let dy = (source.y_max - source.y_min) * percent
    let x_min = source.x_min - dx
    let x_max = source.x_max + dx
    let y_min = source.y_min - dy
    let y_max = source.y_max + dy
    return FRange(x_min, x_max, y_min, y_max)

class ColorWheel:
    var m_index: int = 0
    var m_colors: List[str] = List()

    fn init():
        m_colors.append("red")
        m_colors.append("purple")
        m_colors.append("fuchsia")
        m_colors.append("green")
        m_colors.append("lime")
        m_colors.append("navy")
        m_colors.append("blue")

    fn get_color() -> str:
        if m_colors.is_empty():
            # Initialize on first usage:
            init()

        let color = m_colors.get(index: m_index)
        m_index += 1
        if m_index >= m_colors.len():
            m_index = 0
        return color

struct FVal:
    value: float
    distance: float

fn new_fval(value: float, approx: float) -> FVal:
    return FVal(value, distance: fabs(approx - value))

fn cmp_fval(a: FVal, b: FVal) -> bool:
    return a.distance < b.distance

struct TickValue:
    value: float
    text: str

fn calc_tick_values(axis: Axis, n_ticks: int) -> List[TickValue]:
    # Given the current axis, calculate sensible
    # tick spacing.
    assert(condition: n_ticks > 1, message: "We require at least two n ticks")

    let domain = axis.domain()
    let scale = floor(log10(domain))
    let approx = powf(10.0, -scale) * (domain / float(n_ticks))

    # Snap to fixed values:
    let options: List[FVal] = List()
    options.append(new_fval(value: 0.1, approx))
    options.append(new_fval(value: 0.2, approx))
    options.append(new_fval(value: 0.5, approx))
    options.append(new_fval(value: 1.0, approx))
    options.append(new_fval(value: 2.0, approx))
    options.append(new_fval(value: 5.0, approx))
    let min_value = find_min_value(values: options, cmp: cmp_fval)
    let best = min_value.value

    let tick_width = best * powf(10.0, scale)
    log_info("domain: {float_to_str(domain)} scale: {float_to_str(scale)} approx: {float_to_str(approx)}")
    log_info("best: {float_to_str(best)} tick_width: {float_to_str(tick_width)}")

    # Use scale and dx to determine tick values
    let x = round_to_multiple(value: axis.lower, base: tick_width)
    x = x - 2 * tick_width
    while x < axis.lower:
        x += tick_width
    
    let digits = 0
    if scale > 0:
        digits = 0
    else:
        digits = int(-scale + 1)
    let tick_values: List[TickValue] = List()
    while x < axis.upper:
        # TODO: use scale to limit amount of decimals
        tick_values.append(TickValue(value: x, text: "{float_to_str2(value: x, digits)}"))
        x += tick_width

    return tick_values

fn round_to_multiple(value: float, base: float) -> float:
    let x = int(value / base)
    return x * base

class ChartDrawer:
    var m_chart: Chart
    var m_canvas: Canvas
    var m_x_ticks: List[Tick] = List()
    var m_y_ticks: List[Tick] = List()
    var m_width: int = 640
    var m_height: int = 480
    var m_axis_tick_size: int = 10

    fn draw():
        calc_x_ticks()
        calc_y_ticks()
        draw_grid()
        draw_curves()
        draw_x_axis()
        draw_y_axis()
        draw_border()

    fn calc_x_ticks():
        let pixels_per_tick = 88
        let n_ticks = m_width / pixels_per_tick
        let tick_values = calc_tick_values(axis: m_chart.m_x_axis, n_ticks)
        for tick in tick_values:
            m_x_ticks.append(Tick(value: to_x_pixel(tick.value), text: tick.text))

    fn calc_y_ticks():
        let pixels_per_tick = 42
        let n_ticks = m_height / pixels_per_tick
        let tick_values = calc_tick_values(axis: m_chart.m_y_axis, n_ticks)
        for tick in tick_values:
            m_y_ticks.append(Tick(value: to_y_pixel(tick.value), text: tick.text))

    fn draw_grid():
        set_width(1)
        set_color("gray")
        for x in m_x_ticks:
            draw_line(x1: x.value, y1: 0, x2: x.value, y2: m_height)
        for y in m_y_ticks:
            draw_line(x1: 0, y1: y.value, x2: m_width, y2: y.value)

    fn draw_x_axis():
        # Draw x-axis:
        set_width(2)
        set_color("black")
        draw_line(x1: 0, y1: m_height, x2: m_width, y2: m_height)
        for x in m_x_ticks:
            draw_line(x1: x.value, y1: m_height - m_axis_tick_size, x2: x.value, y2: m_height)
            draw_text(x: x.value, y: m_height + m_axis_tick_size, text: x.text, halign: HorizontalAnchor.Middle(), valign: VerticalAnchor.Top())
        
    fn draw_y_axis():
        # Draw y-axis:
        set_width(2)
        set_color("black")
        draw_line(x1: m_width, y1: 0, x2: m_width, y2: m_height)
        for y in m_y_ticks:
            draw_line(x1: m_width - m_axis_tick_size, y1: y.value, x2: m_width, y2: y.value)
            draw_text(x: m_width + m_axis_tick_size, y: y.value, text: y.text, halign: HorizontalAnchor.Left(), valign: VerticalAnchor.Middle())

    fn draw_curves():
        for curve in m_chart.m_curves:
            let points: List[Point] = List()
            set_color(curve.color)
            set_width(3)
            for point in curve.points:
                points.append(Point(x: to_x_pixel(point.x), y: to_y_pixel(point.y)))
            draw_path(points)

    fn draw_border():
        set_width(2)
        set_color("black")
        draw_rect(x1: 0, y1: 0, x2: m_width, y2: m_height)

    fn to_x_pixel(value?: float) -> int:
        # Scale float value to pixel using x axis
        let domain = m_chart.m_x_axis.domain()
        let fpix = (value - m_chart.m_x_axis.lower) * (m_width / domain)
        return int(fpix)

    fn to_y_pixel(value?: float) -> int:
        # Scale float value to pixel using y axis
        let domain = m_chart.m_y_axis.domain()
        let fpix = m_height - (value - m_chart.m_y_axis.lower) * (m_height / domain)
        return int(fpix)

    fn draw_path(points: List[Point]):
        let p_iter = points.iter()
        case p_iter.next():
            None:
                pass
            Some(p1):
                loop:
                    case p_iter.next():
                        None:
                            break
                        Some(p2):
                            draw_line(x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y)
                            p1 = p2

    fn set_width(width?: int):
        m_canvas.set_width(width)

    fn set_color(color?: str):
        m_canvas.set_color(color)

    fn draw_line(x1: int, y1: int, x2: int, y2: int):
        m_canvas.draw_line(x1, y1, x2, y2)

    fn draw_rect(x1: int, y1: int, x2: int, y2: int):
        draw_line(x1, y1, x2: x1, y2)
        draw_line(x1: x2, y1, x2, y2)
        draw_line(x1, y1, x2, y2: y1)
        draw_line(x1, y1: y2, x2, y2)

    fn draw_text(x: int, y: int, text: str, halign: HorizontalAnchor, valign: VerticalAnchor):
        m_canvas.draw_text(x, y, text, halign, valign)

struct Tick:
    value: int
    text: str
