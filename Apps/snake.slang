"""
Snake implemented in slang
"""

from std import print
from screen import Screen, new_screen

pub fn main() -> int:
	let game = Game()
	while game.is_running:
		game.draw()
		game.handle_input()
	0

class Game:
	pub var is_running: bool = true
	var width: int = 25
	var height: int = 25
	var head: Position = Position(x: 10, y: 10)
	var screen: Screen = new_screen(width: 320, height: 240)

	var direction: Direction = Direction.Up()

	pub fn draw():
		# screen_clear(0, 0, 255)
		var y = 0
		while y < height:
			var x = 0
			var line = ""
			while x < width:
				var cell = " "
				if y == 0:
					cell = "#"
				elif y == height - 1:
					cell = "#"
				elif x == 0:
					cell = "#"
				elif x == width - 1:
					cell = "#"

				if head.x == x and head.y == y:
					cell = "@"

				line = line + cell + cell
				x += 1
			print(line)
			y += 1

	pub fn move():
		case direction:
			Up:
				head.y -= 1
			Down:
				head.y += 1
			Left:
				head.x -= 1
			Right:
				head.x += 1

	pub fn handle_input():
		is_running = false

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

enum Direction:
	Up
	Down
	Left
	Right

enum Key:
	Left
	Right
