""" Test various x86 encodings. """

from std import print
from outstream import BinaryOutput
from bytes import bytes_from_hex_text
from unittest import assert_bytes_equals, assert_str_equals
import x86

pub fn main() -> int:
	assert_encodes(instruction: x86.Instruction.Ret(), text: "ret", bin: "c3")
	print("OK")
	0

fn assert_encodes(instruction: x86.Instruction, text: str, bin: str):
	let asm = x86.instruction_to_string(instruction)
	assert_str_equals(asm, text)
	let outstream = BinaryOutput()
	outstream.select_section(name: ".text")
	x86.emit_instruction(instruction, out: outstream)
	let object = outstream.get_object()
	let encoded = outstream.get_section(name: ".text").data.to_bytes()
	let expected = bytes_from_hex_text(text: bin)
	assert_bytes_equals(encoded, expected)
