""" Machine code generation.
"""

import sil
import mil
from register_allocation import reg_alloc
from vectype import Vector, new_vector
from listtype import List
from logging import log_debug, log_info
from profiling import Profiler
from report import Report
from optiontype import Option
from elf_file import write_elf
from dbginfo import DbgInfo
from dwarf import gen_debug_info
from outstream import BinaryOutput, DataItem
from isel import Backend, Frame, SelectionContext

pub struct CodegenOptions:
	filename: Option[str]
	report: Report
	profiler: Profiler
	debug: Option[DbgInfo]

pub fn cgen[V](program: sil.Program, backend: Backend[V], options: CodegenOptions):
	options.report.writeln("# Compilation report!")
	options.profiler.enter(name: "Code-gen")
	program.dump(report: options.report)
	let out = BinaryOutput()
	out.set_bitsize(bits: backend.bits)
	let g = Codegen(backend, options)
	g.gen_program(program, out)

	let filename = case options.filename:
		Some(name):
			name
		None:
			"test.elf"

	options.profiler.leave()
	write_elf(filename, object: out.get_object())

class Codegen[V]:
	""" Machine independent code generator """
	var backend: Backend[V]
	var options: CodegenOptions

	pub fn gen_program(program: sil.Program, out: BinaryOutput):
		for ext in program.externs:
			out.import_symbol(name: ext.name)
		out.select_section(name: ".text")
		out.set_allocate()
		out.set_executable()
		for function in program.functions:
			gen_function(function, out)
		out.select_section(name: ".data")
		out.set_allocate()
		out.set_writable()
		out.select_section(name: ".rodata")
		out.set_allocate()
		for blob in program.blobs:
			gen_blob(blob, out)
		case options.debug:
			Some(info):
				gen_debug_info(info, out, emit_data: backend.emit_data)
			None:
				pass
		out.do_fixups(fixer: backend.fixer, is_pic_reloc: backend.is_pic_reloc)

	fn gen_function(function: sil.Function, out: BinaryOutput):
		log_info("Generating code for function {function.name}")
		options.profiler.enter(name: "gen-func-{function.name}")
		let frame = Frame:
			stacksize: function.stacksize
			exit_label: "{function.name}_@exit"
			vregs: new_vector()
		let context = SelectionContext(frame)
		let mfunc = select_function(function, context)
		mil.dump_mfunc(report: options.report, mfunc, to_str: backend.to_str)
		reg_alloc(report: options.report, backend, mfunc, frame)
		log_debug("Materializing instructions")
		out.export_symbol(mfunc.name)
		backend.emit_prologue(frame, out)
		for mblock in mfunc.blocks:
			out.define_label(name: mblock.name)
			for minst in mblock.instructions:
				backend.materializer(context, v: minst, out)
		out.define_label(name: frame.exit_label)
		backend.emit_epilogue(frame, out)
		case options.debug:
			Some(info):
				let end_label = "{function.name}_@exit2"
				out.local_symbol(end_label)
				let dbg_func = info.get_function_by_name(name: function.name)
				dbg_func.start_label = function.name
				dbg_func.end_label = end_label
			None:
				pass
		out.do_fixups(fixer: backend.fixer, is_pic_reloc: backend.is_pic_reloc)
		options.profiler.leave()

	fn select_function(function: sil.Function, context: SelectionContext[V]) -> mil.Function[V]:
		"""Turn abstract instructions into abstract machine specific instructions.
		"""
		let mblocks: Vector[mil.Block[V]] = new_vector()
		backend.enter(context, function)
		for block in function.blocks:
			for instruction in block.instructions:
				backend.selector(context, instruction)
			let jump_targets: List[str] = List()
			case block.instructions.last().op:
				Jump(label):
					jump_targets.append(label)
				JumpIf(lhs, op, rhs, label1, label2):
					jump_targets.append(label1)
					jump_targets.append(label2)
			else:
				pass
			mblocks.append(mil.Block(name: block.name, instructions: context.get_instructions(), jump_targets))
		mil.Function(name: function.name, blocks: mblocks)

	fn gen_blob(blob: sil.DataBlob, out: BinaryOutput):
		let section_name = ".rodata" if blob.readonly else ".data"
		out.select_section(name: section_name)
		if blob.is_local:
			out.local_symbol(name: blob.name)
		else:
			out.export_symbol(name: blob.name)
		for content in blob.contents:
			case content:
				Raw(data):
					out.write_bytes(data)
				Ptr(name):
					backend.emit_data(DataItem.AbsPointer64(name), out)
