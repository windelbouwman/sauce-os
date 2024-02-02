
from canvas import Canvas

class Chart:
    var x_axis: Axis = Axis()

    fn to_svg():
        let c = Canvas()
        c.draw_line(x: 10, y: 10)


class Axis:
    var a: int = 0 
    var b: int = 0 



class ChartDrawer:
    var m_chart: Chart

    fn draw():
        draw_grid()

    fn draw_grid():
        pass
