"""
Snake implemented in slang
"""

from std import sdl_init, sdl_poll, sdl_quit, sdl_input_quit, sdl_draw, sdl_sync

pub fn main() -> int:
	let game = Game()
	game.init()

	sdl_init(title: "Slang!", width: 800, height: 600)
	while game.is_running:
		game.step()
		game.draw()
	sdl_quit()
	0

enum Direction:
	Up
	Down
	Left
	Right

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
		sdl_poll()
		if sdl_input_quit():
			is_running = false

		let head = snake[snake_len - 1]
		let next = Position(x: head.x, y: head.y)

		case direction:
			Up:
				next.y -= 1
			Down:
				next.y += 1
			Left:
				next.x -= 1
			Right:
				next.x += 1

		if snake_len >= 4:
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
		sdl_draw(width, height, pixels: screen)
		sdl_sync(interval: 1000)

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

	pub fn handle_key(key: Key):
		case key:
			Left:
				direction = rotate_left(direction)
			Right:
				direction = rotate_right(direction)

fn rotate_right(d?: Direction) -> Direction:
	case d:
		Up:
			Direction.Right()
		Down:
			Direction.Left()
		Left:
			Direction.Up()
		Right:
			Direction.Down()

fn rotate_left(d?: Direction) -> Direction:
	case d:
		Up:
			Direction.Left()
		Down:
			Direction.Right()
		Left:
			Direction.Down()
		Right:
			Direction.Up()

struct BodyElement:
	position: Position
	next: Option

enum Option:
	Some(value: BodyElement)
	None

struct Position:
	x: int
	y: int

enum Key:
	Left
	Right
