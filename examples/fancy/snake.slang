
# Snake implemented in slang

from std import print

extern fn screen_swap()
extern fn screen_clear(r: int, g: int, b: int)

fn main() -> int:
    let game = Game()
    game.draw()
    let n = 0
    while n < 10:
        if n == 5:
            game.handle_key(key: Key.Left())
        game.move()
        game.draw()
        n += 1
    return 0

class Game:
    var width: int = 25
    var height: int = 25
    var head: Position = Position(x: 10, y: 10)

    var direction: Direction = Direction.Up()

    fn draw():
        screen_clear(0, 0, 255)
        let y = 0
        while y < height:
            let x = 0
            let line = ""
            while x < width:
                let cell = " "
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

    fn move():
        case direction:
            Up:
                head.y -= 1
            Down:
                head.y += 1
            Left:
                head.x -= 1
            Right:
                head.x += 1

    fn handle_key(key: Key):
        case key:
            Left:
                direction = rotate_left(direction)
            Right:
                direction = rotate_right(direction)

fn rotate_right(d?: Direction) -> Direction:
    case d:
        Up:
            return Direction.Right()
        Down:
            return Direction.Left()
        Left:
            return Direction.Up()
        Right:
            return Direction.Down()

fn rotate_left(d?: Direction) -> Direction:
    case d:
        Up:
            return Direction.Left()
        Down:
            return Direction.Right()
        Left:
            return Direction.Down()
        Right:
            return Direction.Up()

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
