module main
"""Brainfuck compiler"""

import std
from std import print
from base.fs import Path, new_path
from base.optiontype import Option, option_unwrap
from base.listtype import List
from base.vectype import Vector, new_vector, new_vector_of_size
from base.utils import panic, unimplemented
from compiler import bc

pub fn main() -> int:
	let options = parse_options()
	if options.show_help:
		show_usage()
		return 0
	if options.filenames.len() != 1:
		show_usage()
		return 1
	let filename = options.filenames.get(index: 0)
	run_bf(filename)
	# let program = bf_to_bc(filename)
	# bc.print_bc_program(program)
	0

fn show_usage():
	print("BrainFuck compiler")
	print("Usage:")
	print("   $ bf.exe [options] file")
	print("Options:")
	print("   -h --help    : show help")

struct Options:
	filenames: List[Path]
	show_help: bool

fn parse_options() -> Options:
	let options = Options:
		filenames: List()
		show_help: false
	var i = 0
	let n = std.get_n_args()
	while i < n:
		let argument = std.get_arg(arg: i)
		i += 1
		if argument == "-h" or argument == "--help":
			options.show_help = true
		else:
			options.filenames.append(new_path(filename: argument))
	options

fn run_bf(filename: Path):
	"""Run brainfuck code in interpreter mode"""
	let text = filename.read_text()
	var pc = 0
	var ptr = 0
	let buffer: Vector[int] = new_vector_of_size(size: 30000, default: 0)
	let loops: Vector[int] = new_vector()
	let n = std.str_len(text)
	var line = ""
	while pc < n:
		let c = std.str_get(text, index: pc)
		pc += 1
		if c == '>':
			ptr += 1
		elif c == '<':
			ptr -= 1
		elif c == '+':
			buffer.set(index: ptr, value: (buffer.get(index: ptr) + 1) % 256)
		elif c == '-':
			buffer.set(index: ptr, value: (buffer.get(index: ptr) - 1 + 256) % 256)
		elif c == '.':
			let c = std.chr(buffer.get(index: ptr))
			if c == '\n':
				print(line)
				line = ""
			else:
				line = line + str(c)
		elif c == ',':
			unimplemented(",")
		elif c == '[':
			if buffer.get(index: ptr) == 0:
				var depth = 1
				while depth > 0:
					let c = std.str_get(text, index: pc)
					pc += 1
					if c == '[':
						depth += 1
					elif c == ']':
						depth -= 1
			else:
				loops.append(pc)
		elif c == ']':
			if buffer.get(index: ptr) == 0:
				loops.drop_last()
			else:
				pc = loops.last()

fn bf_to_bc(filename: Path) -> bc.Program:
	print("Loading {filename}")

	let locals: Vector[bc.Local] = new_vector()
	let instructions: Vector[bc.Instruction] = new_vector()

	let int_type = bc.Type.Int(signed: true, bits: 64)
	let uint8_type = bc.Type.Int(signed: false, bits: 8)

	let text = filename.read_text()
	let buffer_type = bc.Type.Array(element_type: uint8_type)

	locals.append(bc.Local(ty: buffer_type, name: "buffer", writable: true))
	locals.append(bc.Local(ty: int_type, name: "ptr", writable: true))

	for c in text:
		if c == '[':
			unimplemented("[")
		elif c == ']':
			unimplemented("]")
		elif c == '+':
			instructions.append(bc.Instruction.LocalGet(index: 0))
			instructions.append(bc.Instruction.LocalGet(index: 1))
			instructions.append(bc.Instruction.LocalGet(index: 0))
			instructions.append(bc.Instruction.LocalGet(index: 1))
			instructions.append(bc.Instruction.GetIndex())
			instructions.append(bc.Instruction.Literal(literal: bc.LiteralValue.Int(value: 1)))
			instructions.append(bc.Instruction.Binop(op: bc.BinaryOperator.Add(), ty: uint8_type))
			instructions.append(bc.Instruction.SetIndex())
		elif c == '-':
			instructions.append(bc.Instruction.LocalGet(index: 0))
			instructions.append(bc.Instruction.LocalGet(index: 1))
			instructions.append(bc.Instruction.LocalGet(index: 0))
			instructions.append(bc.Instruction.LocalGet(index: 1))
			instructions.append(bc.Instruction.GetIndex())
			instructions.append(bc.Instruction.Literal(literal: bc.LiteralValue.Int(value: 1)))
			instructions.append(bc.Instruction.Binop(op: bc.BinaryOperator.Sub(), ty: uint8_type))
			instructions.append(bc.Instruction.SetIndex())
		elif c == '>':  # increment data pointer
			instructions.append(bc.Instruction.LocalGet(index: 1))
			instructions.append(bc.Instruction.Literal(literal: bc.LiteralValue.Int(value: 1)))
			instructions.append(bc.Instruction.Binop(op: bc.BinaryOperator.Add(), ty: int_type))
			instructions.append(bc.Instruction.LocalSet(index: 1))
		elif c == '<':  # decrement data pointer
			instructions.append(bc.Instruction.LocalGet(index: 1))
			instructions.append(bc.Instruction.Literal(literal: bc.LiteralValue.Int(value: 1)))
			instructions.append(bc.Instruction.Binop(op: bc.BinaryOperator.Sub(), ty: int_type))
			instructions.append(bc.Instruction.LocalSet(index: 1))
		elif c == '.':
			unimplemented(".")
		elif c == ',':
			unimplemented(",")

	let function = bc.Function:
		is_pub: true
		name: "main"
		parameters: new_vector()
		return_types: new_vector()
		no_return: false
		locals
		instructions

	# Create bytecode program:
	let extern_functions: Vector[bc.ExternFunction] = new_vector()
	let globals: Vector[bc.Global] = new_vector()
	let structs: Vector[bc.Struct] = new_vector()
	let functions: Vector[bc.Function] = new_vector()

	functions.append(function)

	bc.Program:
		extern_functions
		globals
		structs
		functions
