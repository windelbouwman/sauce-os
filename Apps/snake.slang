"""
Snake implemented in slang
"""

from math import fmin, fmax
import gfx

pub fn main() -> int:
	let game = Game()
	game.init()

	gfx.init(title: "Slang!", width: 800, height: 600)
	while game.is_running:
		game.step()
		game.draw()
	gfx.quit()
	0

enum Direction:
	Up
	Down
	Left
	Right

struct Position:
	x: int
	y: int

class Game:
	pub var is_running: bool = true

	# World
	var width: int = 40
	var height: int = 30

	# 0 -> empty
	# 1 -> wall
	# 2 -> snake
	var world:  [uint8] = [40*30 : uint8]

	# Graphics
	var screen: [uint8] = [40*30*3 : uint8]

	# Snake
	var direction: Direction = Direction.Up()
	var snake_len: int = 0
	var snake: [Position] = [40*30:Position]

	pub fn init():
		var i = 0
		var y = 0
		while y < height:
			var x = 0
			while x < width:
				if y == 0 or y == height - 1 or x ==0 or x == width - 1:
					world[i] = uint8(1)
				else:
					world[i] = uint8(0)
				x += 1
				i += 1
			y += 1

		snake_len = 1
		snake[0] = Position(x: width / 2, y: height / 2)
		cell_put(x: snake[0].x, y: snake[0].y, value:2)

	fn cell_at(x: int , y: int) -> int:
		int(world[y*width + x])

	fn cell_put(x: int, y: int, value:int):
		world[y*width + x] = uint8(value)

	pub fn step():
		# Gather Input
		gfx.poll()

		if gfx.input_click(key: gfx.Key.KEY_APP_QUIT()):
			is_running = false

		let head = snake[snake_len - 1]
		let next = Position(x: head.x, y: head.y)

		let last_direction = direction

		if last_direction != Direction.Down() and (gfx.input_click(key: gfx.Key.KEY_W()) or gfx.input_click(key: gfx.Key.KEY_I())):
			direction = Direction.Up()

		if last_direction != Direction.Up() and (gfx.input_click(key: gfx.Key.KEY_S()) or gfx.input_click(key: gfx.Key.KEY_K())):
			direction = Direction.Down()

		if last_direction != Direction.Right() and (gfx.input_click(key: gfx.Key.KEY_A()) or gfx.input_click(key: gfx.Key.KEY_J())):
			direction = Direction.Left()

		if last_direction != Direction.Left() and (gfx.input_click(key: gfx.Key.KEY_D()) or gfx.input_click(key: gfx.Key.KEY_L())):
			direction = Direction.Right()

		case direction:
			Up:
				next.y -= 1
			Down:
				next.y += 1
			Left:
				next.x -= 1
			Right:
				next.x += 1

		if snake_len >= 4 and not gfx.input_down(key: gfx.Key.KEY_G()):
			shrink()

		let cell = cell_at(x: next.x, y: next.y)

		if cell == 1 or cell == 2:
			is_running = false

		grow(x: next.x, y: next.y)

	fn shrink():
		cell_put(x: snake[0].x, y: snake[0].y, value: 0)
		var i = 0
		while i < snake_len - 1:
			snake[i].x = snake[i + 1].x
			snake[i].y = snake[i + 1].y
			i += 1
		snake_len -= 1

	fn grow(x: int, y: int):
		snake_len += 1
		let i = snake_len - 1
		snake[i] = Position(x: x, y: y)
		cell_put(x: x, y: y, value: 2)


	pub fn draw():
		var i = 0
		var j = 0
		while i < width*height:
			if world[i] == uint8(1):
				screen[j + 0] = uint8(255)
				screen[j + 1] = uint8(255)
				screen[j + 2] = uint8(255)
			elif world[i] == uint8(2):
				screen[j + 0] = uint8(0)
				screen[j + 1] = uint8(255)
				screen[j + 2] = uint8(0)
			else:
				screen[j + 0] = uint8(0)
				screen[j + 1] = uint8(0)
				screen[j + 2] = uint8(0)
			i += 1
			j += 3
		screen[3*0 + 0] = uint8(255)
		screen[3*1 + 1] = uint8(255)
		screen[3*2 + 2] = uint8(255)
		gfx.draw(width, height, pixels: screen)

		let speed = snake_len
		gfx.sync(interval: 0.1 + 1 / (1 + fmax(0, snake_len - 4)))

	pub fn move():
		case direction:
			Up:
				snake[0].y -= 1
			Down:
				snake[0].y += 1
			Left:
				snake[0].x -= 1
			Right:
				snake[0].x += 1

