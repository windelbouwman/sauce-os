""" Test RISCV encoding """

from std import print
import riscv
from outstream import BinaryOutput
from bytes import bytes_from_hex_text
from unittest import assert_bytes_equals, assert_str_equals

pub fn main() -> int:
	assert_encodes(instruction: riscv.Instruction.EBREAK(), text: "ebreak", bin: "73 00 10 00")
	assert_encodes(instruction: riscv.Instruction.ECALL(), text: "ecall", bin: "73 00 00 00")
	assert_encodes(instruction: riscv.Instruction.Store(op: riscv.StoreOp.SW(), rs1: 12, rs2: 31, imm: 29), text: "sw t6, 29(a2)", bin: "a3 2e f6 01")
	assert_encodes(instruction: riscv.Instruction.ThreeRegsOp(op: riscv.RegOp.XOR(), rd: 6, rs1: 11, rs2: 18), text: "xor t1, a1, s2", bin: "33 c3 25 01")
	# TODO:
	# assert_encodes(instruction: riscv.Instruction.LI(rd: 30, imm: 0xFACE), text: "li t5, 64206", bin: "37 0f 01 00 1b 0f ef ac")
	assert_encodes(instruction: riscv.Instruction.LI(rd: 5, imm: 42), text: "li t0, 42", bin: "93 02 a0 02")
	assert_encodes(instruction: riscv.Instruction.RegImm(op: riscv.ImmOp.ADDI(), rd: 2, rs1: 2, imm: -16), text: "addi sp, sp, -16", bin: "13 01 01 ff")
	assert_encodes(instruction: riscv.Instruction.RegImm(op: riscv.ImmOp.ADDI(), rd: 2, rs1: 2, imm: 16), text: "addi sp, sp, 16", bin: "13 01 01 01")
	print("OK")
	0

fn assert_encodes(instruction: riscv.Instruction, text: str, bin: str):
	let asm = riscv.instruction_to_string(instruction)
	assert_str_equals(asm, text)
	let outstream = BinaryOutput()
	outstream.select_section(name: ".text")
	riscv.do_emit(instruction, outstream)
	let object = outstream.get_object()
	let encoded = outstream.get_section(name: ".text").data.to_bytes()
	let expected = bytes_from_hex_text(text: bin)
	assert_bytes_equals(encoded, expected)
