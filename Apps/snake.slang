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


let SOUND_RATE: int = 48000
let SOUND_BUF_LEN: int = SOUND_RATE

let WORLD_WIDTH:  int = 40
let WORLD_HEIGHT: int = 30

let CELL_EMPTY: uint8 =  0
let CELL_WALL:  uint8 =  1
let CELL_SNAKE: uint8 =  2
let CELL_FOOD:  uint8 =  3

class Game:
	pub var is_running: bool = true

	# Game world
	var world:  [uint8] = [WORLD_WIDTH * WORLD_HEIGHT : uint8]

	# Graphics
	var screen: [uint8] = [WORLD_WIDTH * WORLD_HEIGHT * 3 : uint8]

	# Snake
	var direction: Direction = Direction.Up()
	var snake_len:    int = 0
	var snake_target: int = 4

	# An ordered sequence of snake body parts
	var snake: [Position] = [WORLD_WIDTH*WORLD_HEIGHT:Position]

	# Buffer for playing sounds (max 1 second)
	# Passed to gfx.play()
	var sound_buf: [int16] = [SOUND_BUF_LEN:int16]

	pub fn init():
		var i = 0
		var y = 0
		while y < WORLD_HEIGHT:
			var x = 0
			while x < WORLD_WIDTH:
				if y == 0 or y == WORLD_HEIGHT - 1 or x ==0 or x == WORLD_WIDTH - 1:
					world[i] = CELL_WALL
				else:
					world[i] = CELL_EMPTY
				x += 1
				i += 1
			y += 1

		snake_target = 4
		snake_len = 1
		snake[0] = Position(x: WORLD_WIDTH / 2, y: WORLD_HEIGHT / 2)
		cell_put(x: snake[0].x, y: snake[0].y, value:CELL_SNAKE)
		play_sound(freq: 880.0, duration: 0.2)
		gfx.sync(interval: 1)

	pub fn play_sound(freq: float, duration: float):
		# Constants
		let I16_MAX = 32767
		let sample_count = math.min(a: int(SOUND_RATE * duration), b: SOUND_BUF_LEN)

		# Time between samples
		let dt = 1.0 / SOUND_RATE

		var sample_ix = 0
		var phase = 0.0
		var t = 0.0
		while sample_ix < sample_count:
			# Simple pure sound
			let v = math.sin(phase*math.pi*2)*t
			sound_buf[sample_ix] = int16(v * I16_MAX)

			# Limit phase from 0-1 to keep precision
			phase += dt*freq
			phase -= float(int(phase))
			sample_ix += 1
			t += dt / duration
		gfx.play(count: sample_count, samples: sound_buf)

	fn cell_at(x: int , y: int) -> int:
		int(world[y*WORLD_WIDTH + x])

	fn cell_put(x: int, y: int, value:uint8):
		world[y*WORLD_WIDTH + x] = value

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
		while i < WORLD_WIDTH*WORLD_HEIGHT:
			if world[i] == uint8(0):
				empty_count += 1

			if world[i] == uint8(3):
				food_count += 1
			i += 1

		if food_count < 4:
			var food_ix = int(empty_count * rand_float())

			var i = 0
			while i < WORLD_WIDTH*WORLD_HEIGHT:
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
		cell_put(x: snake[0].x, y: snake[0].y, value: CELL_EMPTY)
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
		cell_put(x: x, y: y, value: CELL_SNAKE)


	pub fn draw():
		var i = 0
		var j = 0
		while i < WORLD_WIDTH*WORLD_HEIGHT:
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
		gfx.draw(width: WORLD_WIDTH, height: WORLD_HEIGHT, pixels: screen)

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

