import sil
import mil
from std import print
from register_allocation import reg_alloc
from hashmap import HashMap, new_hashmap_str
from vectype import Vector, new_vector # , vec1
from settype import Set, new_str_set
from listtype import List
from optiontype import Option
from sorting import sort_list
from utils import unimplemented, panic
from logging import log_info
# from strlib import int_to_hex_string
from hexfile import HexFile
from elf_file import write_elf
from bytes import ByteArray
from outstream import BinaryOutput, Section

pub fn cgen(program: sil.Program, backend: Backend, filename: Option[str]):
	program.dump()
	let outstream = BinaryOutput()
	let g = CodegenV1(backend)
	g.gen_program(program, outstream)

	let text_section = outstream.get_section(name: ".text")
	let sections: List[Section] = List()
	sections.append(text_section)

	# log_info("Create {code.data.len()} bytes of binary code")
	let filename2 = case filename:
		Some(name):
			name
		None:
			"test.elf"

	write_elf(filename: filename2, code: sections)

pub struct Backend:
	""" Set with machine specific functions """
	selector: fn(SelectionContextV1, sil.Instruction)
	emit_prologue: fn(Frame, BinaryOutput)
	emit_epilogue: fn(Frame, BinaryOutput)

pub struct BackendV2[I]:
	""" Backend based on first instruction selection, then register allocation. """
	selector: fn(SelectionContextV2[I], sil.Instruction)
	materializer: fn(mil.Instruction[I]) -> I
	instruction_as_str: fn(I) -> str
	to_binstream: fn(I, BinaryOutput)
	emit_prologue: fn(BinaryOutput)
	emit_epilogue: fn(BinaryOutput)

pub struct Frame:
	stacksize: int

pub class SelectionContextV1:
	var m_reg_mapping: HashMap[str,int]
	pub var m_outstream: BinaryOutput

	pub fn get_reg(name?: str) -> int:
		# case value:
		# 	Tmp(name):
		m_reg_mapping.get(key: name)
		# else:
		# 	panic("Oi")

pub class SelectionContextV2[I]:
	var codes: Vector[mil.Instruction[I]] = new_vector()
	var m_counter: int = 0
	# var m_x

	pub fn get_value_vreg(value?: sil.Value) -> mil.Register:
		new_vreg(kind: 0)

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
		m_counter += 1
		mil.Register(id: m_counter, color: 0, kind)

fn calculate_live_ranges(function: sil.Function) -> List[LiveRange]:
	""" Given a function, determine a list of live ranges """
	let lrc = LiveRangeCalculator()
	lrc.calculate(function)

struct LiveRange:
	name: str
	begin: int
	end: int

fn cmp_live_range(a: LiveRange, b: LiveRange) -> bool:
	a.begin < b.begin

class LiveRangeCalculator:
	var x: int = 0
	var starting_pos: HashMap[str,int] = new_hashmap_str()
	var closing_pos: HashMap[str,int] = new_hashmap_str()
	var names: Set[str] = new_str_set()

	pub fn calculate(function: sil.Function) -> List[LiveRange]:
		for p in function.parameters:
			def(p)

		for block in function.blocks:
			x = block.instructions.len() + 1
			for instruction in block.instructions.reversed():
				# print(" >> {instruction}")
				x -= 1
				case instruction.op:
					Nop:
						pass
					Const(dst, value):
						def(dst)
					Alloc(addr, size):
						def(addr)
					Binop(dst, op2, lhs, rhs):
						use(lhs)
						use(rhs)
						def(dst)
					Compare(dst, op, lhs, rhs):
						use(lhs)
						use(rhs)
						def(dst)
					Load(dst, addr):
						use(addr)
						def(dst)
					Store(addr, value):
						use(addr)
						use(value)
					Jump(label):
						pass
					JumpNonZero(condition, label1, label2):
						use(condition)
					Call(dst, callee, arguments):
						case dst:
							Some(v):
								def(v)
							None:
								pass
						use(callee)
						for arg in arguments:
							use(arg)
					Return(value):
						case value:
							Some(v):
								use(v)
							None:
								pass
					Halt:
						pass

		let ranges: List[LiveRange] = List()
		for name in names:
			let begin = starting_pos.get(key: name)
			let end = closing_pos.get(key: name)
			# print("{name}  {begin}...{end}")
			let r = LiveRange(name, begin, end)
			ranges.append(r)
		ranges

	fn use(value?: sil.Value):
		case value:
			Tmp(name):
				close_range(name)
		else:
			pass

	fn def(value?: sil.Value):
		case value:
			Tmp(name):
				start_range(name)
		else:
			pass

	fn start_range(name: str):
		# print("> {x} open {name}")
		names.add(name)
		if not starting_pos.contains(key: name):
			starting_pos.insert(key: name, value: x)

	fn close_range(name: str):
		# print("> {x} close {name}")
		names.add(name)
		if not closing_pos.contains(key: name):
			closing_pos.insert(key: name, value: x)

fn linear_scan(ranges: List[LiveRange], available_regs: List[int], pre_colored: HashMap[str,int]) -> HashMap[str,int]:
	""" Assign registers in linear scan fashion. """
	let sorted_ranges = sort_list(ranges, cmp: cmp_live_range)
	let active_ranges: HashMap[str,LiveRange] = new_hashmap_str()
	let assigned_regs: HashMap[str,int] = new_hashmap_str()
	for range in sorted_ranges:
		# Remove finished ranges from active set:
		let to_be_removed: List[LiveRange] = List()
		for active in active_ranges:
			let active_range = active_ranges.get(key: active)
			if active_range.end < range.begin:
				to_be_removed.append(active_range)
		for to_remove_range in to_be_removed:
			active_ranges.drop(key: to_remove_range.name)
			let reg = assigned_regs.get(key: to_remove_range.name)
			available_regs.prepend(reg)

		# Pick a register and add range to the active set
		let reg = if pre_colored.contains(key: range.name):
			pre_colored.get(key: range.name)
		else:
			available_regs.pop_front()
		print("---> range {range.name} {range.begin}..{range.end} == reg {reg}")
		assigned_regs.insert(key: range.name, value: reg)
		active_ranges.insert(key: range.name, value: range)
	assigned_regs

class CodegenV1:
	""" Machine independent code generator """
	var backend: Backend

	pub fn gen_program(program: sil.Program, outstream: BinaryOutput):
		outstream.select_section(name: ".text")
		for function in program.functions:
			gen_function(function, outstream)

	fn gen_function(function: sil.Function, outstream: BinaryOutput):
		""" Linear scan attempt """
		# Step 1: determine live ranges:
		let ranges = calculate_live_ranges(function)

		let rax = 0
		let rcx = 1
		let rdx = 2
		let rbx = 3
		let rsp = 4
		let rbp = 5
		let rsi = 6
		let rdi = 7
		let available_regs: List[int] = List()
		available_regs.append(rcx)
		available_regs.append(rdx)
		available_regs.append(rbx)

		let parameter_regs: List[int] = List()
		parameter_regs.append(rdi) # arg 1
		parameter_regs.append(rsi) # arg 2
		let pre_colored: HashMap[str,int] = new_hashmap_str()
		var index = 0
		for p in function.parameters:
			case p:
				Tmp(name):
					pre_colored.insert(key: name, value: parameter_regs.get(index))
					index += 1
			else:
				panic("Oi")

		# Step 2: process live ranges by begin point:
		let assigned_registers = linear_scan(ranges, available_regs, pre_colored)

		let frame = Frame(stacksize: function.stacksize)

		outstream.export_symbol(function.name)
		backend.emit_prologue(frame, outstream)
		let context = SelectionContextV1(m_reg_mapping: assigned_registers, m_outstream: outstream)
		for block in function.blocks:
			for instruction in block.instructions:
				backend.selector(context, instruction)
		backend.emit_epilogue(frame, outstream)

class CodegenV2[I]:
	""" Machine independent code generator """
	var backend: BackendV2[I]

	pub fn gen_program(program: sil.Program, outstream: BinaryOutput):
		outstream.select_section(name: ".text")
		for function in program.functions:
			gen_function(function, outstream)

	fn gen_function(function: sil.Function, outstream: BinaryOutput):
		# Instruction selection
		let mfunc = select_function(function)

		# register allocation
		reg_alloc(mfunc)

		# Instantiate actual instructions (instructions and registers are now determined):
		print("Machine Function: {mfunc.name}:")
		outstream.export_symbol(mfunc.name)
		backend.emit_prologue(outstream)
		for mblock in mfunc.blocks:
			print("  Machine Block: {mblock.name}:")
			# TODO
			for minst in mblock.instructions:
				let instruction = backend.materializer(v: minst)
				let txt = backend.instruction_as_str(instruction)
				print("   > {txt}")
			# 	print("   {riscv.instruction_to_string(instruction)}")
				backend.to_binstream(instruction, outstream)
		backend.emit_epilogue(outstream)

	fn select_function(function: sil.Function) -> mil.Function[I]:
		"""Turn abstract instructions into machine specific instructions.

		Machine specific instructions still have unchosen registers.
		"""
		let mblocks: Vector[mil.Block[I]] = new_vector()
		for block in function.blocks:
			let context = SelectionContextV2()
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
