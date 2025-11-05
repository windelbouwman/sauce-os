""" Machine code generation.
"""

import sil
import mil
from register_allocation import reg_alloc
from vectype import Vector, new_vector
from hashmap import HashMap, new_hashmap_str
from strlib import str_join
from bytes import ByteArray
from logging import log_debug
from utils import unimplemented
from listtype import List
from report import Report
from optiontype import Option
from elf_file import write_elf
from outstream import BinaryOutput

pub fn cgen[V](program: sil.Program, backend: Backend[V], filename: Option[str], report: Report):
	report.writeln("# Compilation report!")
	program.dump(report)
	let out = BinaryOutput()
	let g = Codegen(backend, report)
	g.gen_program(program, out)

	let filename2 = case filename:
		Some(name):
			name
		None:
			"test.elf"

	write_elf(filename: filename2, object: out.get_object())

pub struct Backend[V]:
	""" Backend based on first instruction selection, then register allocation. """
	all_regs: List[int]
	enter: fn(SelectionContext[V], sil.Function)
	selector: fn(SelectionContext[V], sil.Instruction)
	to_str: fn(V) -> str
	materializer: fn(mil.Instruction[V], BinaryOutput)
	emit_prologue: fn(Frame, BinaryOutput)
	emit_epilogue: fn(Frame, BinaryOutput)
	fixer: fn(ByteArray, int, int, int, int)

pub struct Frame:
	stacksize: int

pub class SelectionContext[V]:
	var codes: Vector[mil.Instruction[V]] = new_vector()
	var m_tmp_regs: HashMap[str,mil.Register] = new_hashmap_str()
	var m_counter: int = 0

	pub fn get_value_vreg(value?: sil.Value) -> mil.Register:
		case value:
			Tmp(name):
				get_vreg_for_tmp(name)

	pub fn get_vreg_for_tmp(name: str) -> mil.Register:
		if m_tmp_regs.contains(key: name):
			m_tmp_regs.get(key: name)
		else:
			let r = new_vreg(kind: 0)
			m_tmp_regs.insert(key: name, value: r)
			r

	pub fn emit(instruction?: V):
		let uses: Vector[mil.Register] = new_vector()
		let defs: Vector[mil.Register] = new_vector()
		emit_full(instruction, uses, defs)

	fn emit_full(instruction?: V, uses: Vector[mil.Register], defs: Vector[mil.Register]):
		# let relocation: Option[riscv.Relocation] = Option.None()
		let minst = mil.Instruction(instruction, uses, defs)
		codes.append(minst)

	pub fn emit_and_get(instruction?: V) -> mil.Instruction:
		emit(instruction)
		codes.last()

	pub fn get_instructions() -> Vector[mil.Instruction[V]]:
		let res = codes
		codes = new_vector()
		res

	pub fn new_vreg(kind: int) -> mil.Register:
		m_counter += 1
		let color = -1
		mil.Register(id: m_counter, color, kind)

class Codegen[V]:
	""" Machine independent code generator """
	var backend: Backend[V]
	var report: Report

	pub fn gen_program(program: sil.Program, out: BinaryOutput):
		for ext in program.externs:
			out.import_symbol(name: ext.name)
		out.select_section(name: ".text")
		for function in program.functions:
			gen_function(function, out)
		out.select_section(name: ".rodata")
		for blob in program.blobs:
			out.export_symbol(name: blob.name)
			out.write_bytes(data: blob.data)

	fn gen_function(function: sil.Function, out: BinaryOutput):
		let frame = Frame(stacksize: function.stacksize)
		let mfunc = select_function(function)
		dump_mfunc(mfunc)
		reg_alloc(mfunc, all_regs: backend.all_regs)
		log_debug("Materializing instructions")
		out.export_symbol(mfunc.name)
		backend.emit_prologue(frame, out)
		for mblock in mfunc.blocks:
			out.define_label(name: mblock.name)
			for minst in mblock.instructions:
				backend.materializer(v: minst, out)
		backend.emit_epilogue(frame, out)
		out.do_fixups(fixer: backend.fixer)

	fn select_function(function: sil.Function) -> mil.Function[V]:
		"""Turn abstract instructions into abstract machine specific instructions.
		"""
		let mblocks: Vector[mil.Block[V]] = new_vector()
		let context = SelectionContext()
		backend.enter(context, function)
		for block in function.blocks:
			for instruction in block.instructions:
				backend.selector(context, instruction)
			mblocks.append(mil.Block(name: block.name, instructions: context.get_instructions()))
		mil.Function(name: function.name, blocks: mblocks)

	fn dump_mfunc(mfunc: mil.Function[V]):
		if not report.is_enabled():
			return
		report.writeln("----======================----")
		report.writeln("--- Function '{mfunc.name}")
		for mblock in mfunc.blocks:
			report.writeln("  Block '{mblock.name}'")
			for minst in mblock.instructions:
				let txt = backend.to_str(minst.instruction)
				let defs = reg_to_str(regs: minst.defs)
				let uses = reg_to_str(regs: minst.uses)
				report.writeln("    > {txt}                        defs=[{defs}] uses=[{uses}]")
		report.writeln("")

fn reg_to_str(regs: Vector[mil.Register]) -> str:
	let parts: List[str] = List()
	for r in regs:
		parts.append("{r.id}")
	str_join(parts, sep: ", ")
