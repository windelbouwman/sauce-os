""" A slang port of doom.

This is a long shot: try a software renderer.

"""

from logging import set_log_level
from std import print
from math import sin, cos, radians
from screen import new_screen
from game import Engine, new_cube_mesh

pub fn main() -> int:
	print("Hello world")
	set_log_level(level: 5)
	let s = new_screen(width: 320, height: 240)
	s.set_color(red: 0, green: 128, blue: 128)
	s.clear()
	s.set_color(red: 255, green: 0, blue: 0)
	s.draw_line(x1: 10, y1: 10, x2: 10, y2: 30) # vertical line
	s.draw_line(x1: 20, y1: 10, x2: 50, y2: 10) # horizontal line

	s.draw_line(x1: 10, y1: 30, x2: 310, y2: 10) # upwards line
	s.draw_line(x1: 10, y1: 30, x2: 310, y2: 50) # Downwards line

	s.draw_line(x1: 160, y1: 10, x2: 150, y2: 230) # Left line
	s.draw_line(x1: 160, y1: 10, x2: 170, y2: 230) # Right line

	s.set_color(red: 255, green: 255, blue: 0)
	var a = 0
	while a < 360:
		let x = 160 + int(100 * cos(radians(degrees: a)))
		let y = 120 + int(100 * sin(radians(degrees: a)))
		s.draw_line(x1: 160, y1: 120, x2: x, y2: y) # Right line
		a += 12

	let m = new_cube_mesh()
	let e = Engine(m_screen: s)
	e.set_projection_matrix(fov: 90, near: 0.1, far: 100.0)
	e.draw_mesh(m)

	s.save_png(filename: "doom.png")
	print("Exit..")
	0
