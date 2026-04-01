module main

from std import print
from base.utils import panic
from base.unittest import assert_int_equals
from compiler.parsing.parsing import parse_expr_from_text, ParseError
from compiler.basepass import IdGen
from compiler import ast
from compiler.location import get_begin, get_end

pub fn main() -> int:
	test_parse_13()
	print("OK")
	0

fn test_parse_13():
	let source = "13 + 33"
	let id_gen = IdGen()
	let typectx = ast.make_typectx()
	try:
		let res = parse_expr_from_text(source, id_gen, typectx)
		assert_int_equals(get_begin(res.location), 0)
		assert_int_equals(get_end(res.location), 6)
	except (a: ParseError):
		panic("Should not raise exception")
