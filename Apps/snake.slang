"""
Snake implemented in slang
"""

import gfx
import std
import math
from rand import Rand
from listtype import List

pub fn main() -> int:
	gfx.init(title: "Slang!", width: 800, height: 600)

	let game = Game()
	game.init()
	while game.is_running:
		game.update()
	gfx.quit()
	0


# Direction
enum Direction:
	Up
	Down
	Left
	Right

fn direction_opposite(direction: Direction) -> Direction:
	case direction:
		Up:
			Direction.Down()
		Down:
			Direction.Up()
		Left:
			Direction.Right()
		Right:
			Direction.Left()

# Position
class Position:
	pub var x: int
	pub var y: int

	fn add(direction: Direction):
		"""Move current point one step towrads the given direction"""
		case direction:
			Up:
				y -= 1
			Down:
				y += 1
			Left:
				x -= 1
			Right:
				x += 1

# World
enum Cell:
	Empty
	Wall
	Snake
	Food

let I16_MAX: int = 32767

let SOUND_RATE: int = 48000
let SOUND_BUF_LEN: int = 48000

let WORLD_WIDTH:  int = 40
let WORLD_HEIGHT: int = 30

class Game:
	pub var is_running: bool = true

	# Game world
	var world:  [Cell] = [WORLD_WIDTH * WORLD_HEIGHT : Cell]

	# Graphics
	var screen: [uint8] = [WORLD_WIDTH * WORLD_HEIGHT * 3 : uint8]

	# Snake
	var direction: Direction = Direction.Up()
	var next_direction: List[Direction] = List()
	var snake_len:    int = 0
	var snake_target: int = 4
	var score: int = 0
	var high_score: int = 0

	# An ordered sequence of snake body parts
	var snake: [Position] = [WORLD_WIDTH*WORLD_HEIGHT:Position]

	# Buffer for playing sounds (max 1 second)
	# Passed to gfx.play()
	var sound_buf: [int16] = [SOUND_BUF_LEN:int16]

	var rand: Rand = Rand()

	pub fn init():
		# seed the rng a bit
		let tmp_1 = rand.next()
		let tmp_2 = rand.next()

		var i = 0
		var y = 0
		while y < WORLD_HEIGHT:
			var x = 0
			while x < WORLD_WIDTH:
				if y == 0 or y == WORLD_HEIGHT - 1 or x ==0 or x == WORLD_WIDTH - 1:
					world[i] = Cell.Wall()
				else:
					world[i] = Cell.Empty()
				x += 1
				i += 1
			y += 1
		snake_len = 0
		score = 0

	fn choose(n?: int, list?: [str]) -> str:
		list[math.modulo(value: int(rand.next()), divisor: n)]

	fn game_over():
		play_sound(freq: 220.0, duration: 0.2)

		let has_highscore = score > high_score
		if has_highscore:
			high_score = score

		var reaction = "..."

		if score < 5:
			reaction = choose(6, [ "That was horrible.", "You play like my grandma.", "Don't forget to connect the keybaord.", "Impressive, for playing blindfolded.", "lol", "Try harder! You can do it!" ])
		elif score < 10:
			reaction = choose(6, [ "Hmm, now we are getting somewhere", "Good, not great", "Well, at least you tried", "Try again, you might still improve", "Ok", "Decent" ])
		elif score < 20:
			reaction = choose(3, [ "Good!", "Nice!", "I see potential" ])
		elif score < 80:
			reaction = choose(3, [ "Wow, very good!", "Amazing!", "You Win!" ])
		else:
			reaction = choose(4, [ "That was awesome!", "Very Amazing!", "You Win!", "You are the ultimate snake champion!" ])

		std.print("")
		std.print("===== Game Over =====")
		if has_highscore:
			std.print(">>>> NEW HIGHSCORE! <<<<")
		std.print("Score: {score}")
		std.print("Best: {high_score}")
		std.print("Conclusion: {reaction}")
		std.print("")

		gfx.sync(interval: 1)
		init()

	pub fn play_sound(freq: float, duration: float):
		# Constants
		let sample_count = math.min(a: int(SOUND_RATE * duration), b: SOUND_BUF_LEN)

		# Time between samples
		let dt = 1.0 / SOUND_RATE

		var sample_ix = 0
		var phase  = 0.0
		var phase1 = 0.0
		var t = 0.0
		while sample_ix < sample_count:
			# Simple pure sound
			let volume = (4*t - 4*t*t) * (0.1 + duration*0.9)
			var v = math.sin(phase*math.pi*2)*volume
			v *= 20
			if v > 1:
				v = 1
			if v < -1:
				v = -1
			v /= 20
			sound_buf[sample_ix] = int16(v * 0.25 * I16_MAX)

			# Limit phase from 0-1 to keep precision
			phase += dt*freq
			phase -= float(int(phase))
			sample_ix += 1
			t += dt / duration
		gfx.play(count: sample_count, samples: sound_buf)

	fn cell_at(x: int , y: int) -> Cell:
		world[y*WORLD_WIDTH + x]

	fn cell_put(x: int, y: int, value:Cell):
		world[y*WORLD_WIDTH + x] = value

	# Game update rate
	var dt: float = 1.0 / 120
	var time_since_step: float = 0

	pub fn update():
		let a = 1.0 / (score + 1)

		let rate_start = 2
		let rate_end   = 10

		let rate = rate_start + (1-1/(1+float(score)/4))*(rate_end - rate_start)
		let step_time = 1 / rate
		input()

		if time_since_step > step_time:
			time_since_step -= step_time
			step()
		time_since_step += dt

		draw()

		gfx.sync(interval: dt)

	pub fn input():
		# Gather Input
		gfx.poll()

		if gfx.input_click(key: gfx.Key.KEY_APP_QUIT()):
			is_running = false

		if gfx.input_click(key: gfx.Key.KEY_UP()) or gfx.input_click(key: gfx.Key.KEY_W()) or gfx.input_click(key: gfx.Key.KEY_I()):
			next_direction.append(Direction.Up())

		if gfx.input_click(key: gfx.Key.KEY_DOWN()) or gfx.input_click(key: gfx.Key.KEY_S()) or gfx.input_click(key: gfx.Key.KEY_K()):
			next_direction.append(Direction.Down())

		if gfx.input_click(key: gfx.Key.KEY_LEFT()) or gfx.input_click(key: gfx.Key.KEY_A()) or gfx.input_click(key: gfx.Key.KEY_J()):
			next_direction.append(Direction.Left())

		if gfx.input_click(key: gfx.Key.KEY_RIGHT()) or gfx.input_click(key: gfx.Key.KEY_D()) or gfx.input_click(key: gfx.Key.KEY_L()):
			next_direction.append(Direction.Right())

	pub fn step():
		# Startup
		if snake_len == 0:
			snake_target = 4
			snake_len = 1
			snake[0] = Position(x: WORLD_WIDTH / 2, y: WORLD_HEIGHT / 2)
			cell_put(x: snake[0].x, y: snake[0].y, value:Cell.Snake())
			play_sound(freq: 880.0, duration: 0.2)
			return

		# Step
		let head = snake[snake_len - 1]
		let next = Position(x: head.x, y: head.y)

		while not next_direction.is_empty():
			let candi = next_direction.pop_front()

			# Skip invalid directions
			if candi == direction_opposite(direction) or candi == direction:
				continue

			direction = candi
			break

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
			case world[i]:
				Empty:
					empty_count += 1
				Food:
					food_count += 1
			else:
				pass
			i += 1

		if food_count < 4:
			var food_ix = int(empty_count * rand.next_float())

			var i = 0
			while i < WORLD_WIDTH*WORLD_HEIGHT:
				if world[i] == Cell.Empty():
					if food_ix == 0:
						world[i] = Cell.Food()
						break
					else:
						food_ix -= 1
				i += 1

		let cell = cell_at(x: next.x, y: next.y)

		# Wall or Snake
		if cell == Cell.Wall() or cell == Cell.Snake():
			game_over()
			return

		# Food
		if cell == Cell.Food():
			snake_target += 4
			score += 1
			play_sound(freq: 220.0 + 440.0*rand.next_float(), duration: 0.2)
		else:
			let duration = 1.0 / math.max(snake_len, 4)
			play_sound(freq: 440.0, duration)

		grow(x: next.x, y: next.y)

	fn shrink():
		cell_put(x: snake[0].x, y: snake[0].y, value: Cell.Empty())
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
		cell_put(x: x, y: y, value: Cell.Snake())


	pub fn draw():
		var i = 0
		var j = 0
		while i < WORLD_WIDTH*WORLD_HEIGHT:
			case world[i]:
				Wall:
					screen[j + 0] = uint8(10)
					screen[j + 1] = uint8(30)
					screen[j + 2] = uint8(10)
				Snake:
					screen[j + 0] = uint8(0)
					screen[j + 1] = uint8(255)
					screen[j + 2] = uint8(0)
				Food:
					screen[j + 0] = uint8(255)
					screen[j + 1] = uint8(0)
					screen[j + 2] = uint8(0)
			else:
				screen[j + 0] = uint8(10)
				screen[j + 1] = uint8(60)
				screen[j + 2] = uint8(10)
			i += 1
			j += 3
		gfx.draw(width: WORLD_WIDTH, height: WORLD_HEIGHT, pixels: screen)
