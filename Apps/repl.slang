
# A slang-lang REPL!

from std import print, read_line
from basepass import IdGen
from parsing import parse_expr_from_text
from location import Position
from errors import CompilationError


fn main() -> int:
    print("Welcome to the slang-lang REPL!")
    let r = Repl()
    loop:
        let line = read_line(prompt: "~~~> ")
        r.eval(line)
        print("Computed result: {line}")
    return 0


class Repl:
    var id_gen: IdGen = IdGen()

    fn eval(line: str):
        # let program = parse_source(filename, id_gen)
        let p1 = Position(row: 1, column: 1)
        try:
            let expr = parse_expr_from_text(source: line, id_gen, p1)
        except (ex: CompilationError):
            print("Oei!")
