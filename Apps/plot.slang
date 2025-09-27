
# A plotting example program.

from logging import log_info, set_log_level
from chart import Chart
from lttb import lttb

pub fn main() -> int:
	set_log_level(level: 2)
	log_info("Plotting curves")
	let c = Chart()
	plot_function(chart: c, name: "y = x", x_min: -10.0, x_max: 10.0, dx: 0.7, f: f_linear)
	plot_function(chart: c, name: "parabole", x_min: -20.0, x_max: 20.0, dx: 0.2, f: f_parabola)
	plot_function(chart: c, name: "y = x^3", x_min: -10.0, x_max: 10.0, dx: 0.1, f: f_cubic)

	# Resample the last curve using the LTTB algorithm:
	let sampled = lttb(values: c.m_curves.last().points, threshold: 6)
	c.add_curve(name: "sampled", points: sampled)

	c.autoscale()
	# c.zoom_out()
	# c.zoom(factor: 0.001)
	c.to_svg(filename: "data-plot.svg")
	0

fn f_linear(x: float) -> float:
	x

fn f_parabola(x: float) -> float:
	(x * x) / 10.0

fn f_cubic(x: float) -> float:
	(x - 4) * x * (x + 4) / 5.0

fn plot_function(chart: Chart, name: str, x_min: float, x_max: float, dx: float, f: fn (float) -> float):
	# Plot a function in the given chart.
	let line = chart.new_curve(name)
	var x = x_min
	while x < x_max:
		let y = f(x)
		line.add_point(x, y)
		x += dx
