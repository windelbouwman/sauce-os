
from std import print
from utils import panic
from unittest import assert_int_equals
from parsing import parse_expr_from_text
from location import Position
from basepass import IdGen
from errors import CompilationError

fn main() -> int:
    test_parse_13()
    print("OK")
    return 0

fn test_parse_13():
    let source = "13"
    let id_gen = IdGen()
    let p1 = Position(row: 5, column: 7)
    try:
        let res = parse_expr_from_text(source, id_gen, p1)
        assert_int_equals(res.location.begin.row, 5)
        assert_int_equals(res.location.begin.column, 7)
        assert_int_equals(res.location.end.row, 5)
        assert_int_equals(res.location.end.column, 8)
    except (a: CompilationError):
        panic("Should not raise exception")
