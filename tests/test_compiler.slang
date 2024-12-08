
from std import print
from utils import panic
from unittest import assert_int_equals
from parsing import parse_expr_from_text
from basepass import IdGen
from errors import CompilationError

pub fn main() -> int:
    test_parse_13()
    print("OK")
    0

fn test_parse_13():
    let source = "13"
    let id_gen = IdGen()
    try:
        let res = parse_expr_from_text(source, id_gen)
        assert_int_equals(res.location.begin, 0)
        assert_int_equals(res.location.end, 1)
    except (a: CompilationError):
        panic("Should not raise exception")
