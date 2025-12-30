""" Test compiler optimization pass.
"""

from std import print
from unittest import assert_true
from vectype import vec1, vec3
from listtype import List
import sil
from opt import skip_jump_blocks

pub fn main() -> int:
	let block_a = sil.Block(name: "A", instructions: vec1(make_jump("B")))
	let block_b = sil.Block(name: "B", instructions: vec1(make_jump("C")))
	let block_c = sil.Block(name: "C", instructions: vec1(make_jump("B")))
	let function = sil.Function(name: "foo", parameters: List(), stacksize: 0, start: block_a, blocks: vec3(block_a, block_b, block_c))
	let changed = skip_jump_blocks(function)
	assert_true(changed)
	print("OK")
	0

fn make_jump(target?: str) -> sil.Instruction:
	sil.Instruction(op: sil.OpCode.Jump(target))
