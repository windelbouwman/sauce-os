"""
Snake implemented in slang
"""

from math import fmin, fmax
import gfx
import math

pub fn main() -> int:
	gfx.init(title: "Slang!", width: 800, height: 600)

	let game = Game()
	game.init()
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

enum Cell:
	Empty
	Wall
	Snake
	Food

struct Position:
	x: int
	y: int

var rand_seed: uint64 = 0

fn rand_next() -> uint32:
	"""
	Generate a random 32 bit number
	range: [0, U32_MAX]
	"""
	rand_seed = uint64(6364136223846793005) * rand_seed + uint64(1)
	let xorshifted = ((rand_seed >> uint64(18)) ^ rand_seed) >> uint64(27)
	let rot = rand_seed >> uint64(59)
	let ret = uint32((xorshifted >> rot) | (xorshifted << ((-rot) & uint64(31))))
	ret

fn rand_float() -> float:
	"""
	Generate a random float
	range: [0, 1)
	"""
	float(rand_next()) / 0x100000000

let CELL_EMPTY : uint8 =  0
let CELL_WALL  : uint8 =  1
let CELL_SNAKE : uint8 =  2
let CELL_FOOD  : uint8 =  3

class Game:
	pub var is_running: bool = true

	# World
	var width: int = 40
	var height: int = 30

	# 0 -> empty
	# 1 -> wall
	# 2 -> snake
	# 3 -> food
	var world:  [uint8] = [40*30 : uint8]

	# Graphics
	var screen: [uint8] = [40*30*3 : uint8]

	# Snake
	var direction: Direction = Direction.Up()
	var snake_len:    int = 0
	var snake_target: int = 4
	var snake: [Position] = [40*30:Position]
	var sound: [int16] = [48000:int16]

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

		snake_target = 4
		snake_len = 1
		snake[0] = Position(x: width / 2, y: height / 2)
		cell_put(x: snake[0].x, y: snake[0].y, value:2)
		gfx.sync(interval: 1)
		play_sound(freq: 880.0, duration: 0.2)

	pub fn play_sound(freq: float, duration: float):
		# Constants
		let i16_max = 32767
		let rate = 48000
		let max_buf = 48000
		let sample_count = math.min(a: int(rate * duration), b: max_buf)

		# Time between samples
		let dt = 1.0 / rate

		var sample_ix = 0
		var phase = 0.0
		while sample_ix < sample_count:
			# Simple pure sound
			let v = math.sin(phase*math.pi*2)
			sound[sample_ix] = int16(v * i16_max)

			# Limit phase from 0-1 to keep precision
			phase += dt*freq
			phase -= float(int(phase))
			sample_ix += 1
		gfx.play(count: sample_count, samples: sound)

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

		if snake_len >= snake_target:
			shrink()

		var i = 0
		var food_count  = 0
		var empty_count = 0
		while i < width*height:
			if world[i] == uint8(0):
				empty_count += 1

			if world[i] == uint8(3):
				food_count += 1
			i += 1

		if food_count < 4:
			var food_ix = int(empty_count * rand_float())

			var i = 0
			while i < width*height:
				if world[i] == uint8(0):
					if food_ix == 0:
						world[i] = uint8(3)
						break
					else:
						food_ix -= 1
				i += 1

		let cell = cell_at(x: next.x, y: next.y)

		# Wall or Snake
		if cell == 1 or cell == 2:
			gfx.sync(interval: 1)
			init()
			return

		# Food
		if cell == 3:
			snake_target += 1
			play_sound(freq: 880.0, duration: 0.1)
		else:
			play_sound(freq: 440.0, duration: 0.1)

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
			elif world[i] == uint8(3):
				screen[j + 0] = uint8(255)
				screen[j + 1] = uint8(255)
				screen[j + 2] = uint8(0)
			else:
				screen[j + 0] = uint8(0)
				screen[j + 1] = uint8(0)
				screen[j + 2] = uint8(0)
			i += 1
			j += 3
		gfx.draw(width, height, pixels: screen)

		let speed = snake_len
		gfx.sync(interval: 0.1 + 0.8 / (1 + fmax(0, snake_len - 4)))

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

