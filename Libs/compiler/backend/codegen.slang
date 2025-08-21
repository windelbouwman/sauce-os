import sil
import mil
from std import print
from register_allocation import reg_alloc
from vectype import Vector, new_vector # , vec1
from utils import log_info  # , unimplemented, panic
# from strlib import int_to_hex_string
from hexfile import HexFile
from elf_file import write_elf
from bytes import ByteArray, Bytes
from outstream import BinaryOutput

pub fn cgen[I](program: sil.Program, backend: Backend[I]):
	program.dump()
	let g = Codegen(backend)
	let code = g.gen_program(program)
	log_info("Create {code.len()} bytes of binary code")
	write_elf(filename: "test.elf", code)
	log_info("OK.")

pub struct Backend[I]:
	""" Set with machine specific functions """
	selector: fn(SelectionContext[I], sil.Instruction)
	materializer: fn(mil.Instruction[I]) -> I
	instruction_as_str: fn(I) -> str
	to_binstream: fn(I, BinaryOutput)

pub class SelectionContext[I]:
	var codes: Vector[mil.Instruction[I]] = new_vector()

	pub fn emit(instruction?: I):
		#let code = riscv.encode_instruction(instruction)
		#print("--> {int_to_hex_string(code)} -> {txt} ")
		# let txt = riscv.instruction_to_string(instruction)
		# print("--> {txt} ")
		let uses: Vector[mil.Register] = new_vector()
		let defs: Vector[mil.Register] = new_vector()
		emit_full(instruction, uses, defs)

	fn emit_full(instruction?: I, uses: Vector[mil.Register], defs: Vector[mil.Register]):
		# let relocation: Option[riscv.Relocation] = Option.None()
		let minst = mil.Instruction(instruction, uses, defs)
		codes.append(minst)

	pub fn emit_and_get(instruction?: I) -> mil.Instruction:
		emit(instruction)
		codes.last()

	pub fn get_instructions() -> Vector[mil.Instruction[I]]:
		codes

	pub fn new_vreg(kind: int) -> mil.Register:
		mil.Register(color: 0, kind)

class Codegen[I]:
	""" Machine independent code generator """
	var backend: Backend[I]

	pub fn gen_program(program: sil.Program) -> Bytes:
		let outstream = BinaryOutput()
		outstream.select_section(name: ".text")
		for function in program.functions:
			gen_function(function, outstream)
		outstream.get_section_data(name: ".text")

	fn gen_function(function: sil.Function, outstream: BinaryOutput):
		# Instruction selection
		let mfunc = select_function(function)

		# register allocation
		reg_alloc(mfunc)

		# Instantiate actual instructions (instructions and registers are now determined):
		print("Machine Function: {mfunc.name}:")
		for mblock in mfunc.blocks:
			print("  Machine Block: {mblock.name}:")
			# TODO
			for minst in mblock.instructions:
				let instruction = backend.materializer(v: minst)
				let txt = backend.instruction_as_str(instruction)
				print("   > {txt}")
			# 	print("   {riscv.instruction_to_string(instruction)}")
				backend.to_binstream(instruction, outstream)

	fn select_function(function: sil.Function) -> mil.Function[I]:
		"""Turn abstract instructions into machine specific instructions.

		Machine specific instructions still have unchosen registers.
		"""
		let mblocks: Vector[mil.Block[I]] = new_vector()
		for block in function.blocks:
			let context = SelectionContext()
			for instruction in block.instructions:
				backend.selector(context, instruction)
			mblocks.append(mil.Block(name: block.name, instructions: context.get_instructions()))
		mil.Function(name: function.name, blocks: mblocks)

	pub fn to_hex() -> HexFile:
		# Gather resulting binary code in a hex file.
		let h = HexFile()
		let b = ByteArray()
		let data = b.to_bytes()
		h.add_bytes(address: 0, data)
		h
