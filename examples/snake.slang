
# Snake implemented in slang

from std import print

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
        let y = 0
        while y < this.height:
            let x = 0
            let line = ""
            while x < this.width:
                let cell = " "
                if y == 0:
                    cell = "#"
                elif y == this.height - 1:
                    cell = "#"
                elif x == 0:
                    cell = "#"
                elif x == this.width - 1:
                    cell = "#"

                if this.head.x == x and this.head.y == y:
                    cell = "@"

                line = line + cell + cell
                x += 1
            print(line)
            y += 1

    fn move():
        case this.direction:
            Up:
                this.head.y -= 1
            Down:
                this.head.y += 1
            Left:
                this.head.x -= 1
            Right:
                this.head.x += 1

    fn handle_key(key: Key):
        case key:
            Left:
                this.direction = rotate_left(this.direction)
            Right:
                this.direction = rotate_right(this.direction)

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
