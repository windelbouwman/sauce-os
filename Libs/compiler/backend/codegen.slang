""" Machine code generation.
"""

import sil
import mil
from register_allocation import reg_alloc
from vectype import Vector, new_vector
from hashmap import HashMap, new_hashmap_str, new_hashmap_int
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
	all_regs: List[int]  # int regs
	all_regs2: List[int]  # Float regs
	enter: fn(SelectionContext[V], sil.Function)
	selector: fn(SelectionContext[V], sil.Instruction)
	to_str: fn(V) -> str
	materializer: fn(SelectionContext[V], mil.Instruction[V], BinaryOutput)
	emit_prologue: fn(Frame, BinaryOutput)
	emit_epilogue: fn(Frame, BinaryOutput)
	fixer: fn(ByteArray, int, int, int, int)
	emit_pointer: fn(str, BinaryOutput)

pub struct Frame:
	stacksize: int
	exit_label: str

pub class SelectionContext[V]:
	var codes: Vector[mil.Instruction[V]] = new_vector()
	var m_tmp_regs: HashMap[str,mil.Register] = new_hashmap_str()
	var m_pre_colored_regs: HashMap[int,mil.Register] = new_hashmap_int()
	var m_counter: int = 0
	pub var frame: Frame

	pub fn get_value_vreg(value?: sil.Value) -> mil.Register:
		get_vreg_for_tmp(name: value.name, ty: value.ty)

	pub fn get_vreg_for_tmp(name: str, ty: sil.Type) -> mil.Register:
		if m_tmp_regs.contains(key: name):
			m_tmp_regs.get(key: name)
		else:
			let kind: int = case ty:
				I64:
					0
				F64:
					1
				PTR:
					0
			let r = new_vreg(kind)
			m_tmp_regs.insert(key: name, value: r)
			r

	pub fn get_pre_colored(color: int, kind: int) -> mil.Register:
		if m_pre_colored_regs.contains(key: color):
			m_pre_colored_regs.get(key: color)
		else:
			let r = new_vreg(kind)
			r.color = color
			m_pre_colored_regs.insert(key: color, value: r)
			r

	pub fn emit(instruction?: V):
		emit_full(instruction)

	fn emit_full(instruction?: V):
		let minst = mil.Instruction(instruction)
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
		out.set_executable()
		for function in program.functions:
			gen_function(function, out)
		out.select_section(name: ".data")
		out.set_writable()
		for blob in program.blobs:
			let section_name = ".rodata" if blob.readonly else ".data"
			out.select_section(name: section_name)
			out.export_symbol(name: blob.name)
			for content in blob.contents:
				case content:
					Raw(data):
						out.write_bytes(data)
					Ptr(name):
						backend.emit_pointer(name, out)
		out.do_fixups(fixer: backend.fixer)

	fn gen_function(function: sil.Function, out: BinaryOutput):
		let frame = Frame(stacksize: function.stacksize, exit_label: "{function.name}_@exit")
		let context = SelectionContext(frame)
		let mfunc = select_function(function, context)
		dump_mfunc(mfunc)
		reg_alloc(mfunc, all_regs: backend.all_regs, all_regs2: backend.all_regs2)
		log_debug("Materializing instructions")
		out.export_symbol(mfunc.name)
		backend.emit_prologue(frame, out)
		for mblock in mfunc.blocks:
			out.define_label(name: mblock.name)
			for minst in mblock.instructions:
				backend.materializer(context, v: minst, out)
		out.define_label(name: frame.exit_label)
		backend.emit_epilogue(frame, out)
		out.do_fixups(fixer: backend.fixer)

	fn select_function(function: sil.Function, context: SelectionContext[V]) -> mil.Function[V]:
		"""Turn abstract instructions into abstract machine specific instructions.
		"""
		let mblocks: Vector[mil.Block[V]] = new_vector()
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
				let defs = regs_to_str(label: "defs", regs: minst.defs)
				let uses = regs_to_str(label: "uses", regs: minst.uses)
				let clobbers = regs_to_str(label: "clobbers", regs: minst.clobbers)
				let is_move = "move" if minst.is_move else ""
				report.writeln("    > {txt}                     {defs} {uses} {clobbers} {is_move}")
		report.writeln("")

fn regs_to_str(label: str, regs: Vector[mil.Register]) -> str:
	if regs.is_empty():
		""
	else:
		let parts: List[str] = List()
		for reg in regs:
			parts.append(mil.vr_to_str(reg))
		let txt = str_join(parts, sep: ", ")
		"{label}=[{txt}]"
