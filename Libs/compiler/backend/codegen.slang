""" Machine code generation.
"""

import sil
import mil
from register_allocation import reg_alloc
from vectype import Vector, new_vector
from logging import log_debug, log_info
from report import Report
from optiontype import Option
from elf_file import write_elf
from outstream import BinaryOutput
from isel import Backend, Frame, SelectionContext

pub struct CodegenOptions:
	filename: Option[str]
	report: Report
	debug: bool

pub fn cgen[V](program: sil.Program, backend: Backend[V], options: CodegenOptions):
	options.report.writeln("# Compilation report!")
	program.dump(report: options.report)
	let out = BinaryOutput()
	let g = Codegen(backend, options)
	g.gen_program(program, out)

	let filename = case options.filename:
		Some(name):
			name
		None:
			"test.elf"

	write_elf(filename, object: out.get_object())

class Codegen[V]:
	""" Machine independent code generator """
	var backend: Backend[V]
	var options: CodegenOptions

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
			gen_blob(blob, out)
		if options.debug:
			gen_debug_info(out)
		out.do_fixups(fixer: backend.fixer, is_pic_reloc: backend.is_pic_reloc)

	fn gen_debug_info(out: BinaryOutput):
		""" Generate debug info """
		log_info("Creating debug info")
		out.select_section(name: ".debug_info")
		# TODO: Create DWARF debug information

	fn gen_function(function: sil.Function, out: BinaryOutput):
		log_info("Generating code for function {function.name}")
		let frame = Frame(stacksize: function.stacksize, exit_label: "{function.name}_@exit")
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
		out.do_fixups(fixer: backend.fixer, is_pic_reloc: backend.is_pic_reloc)

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
					backend.emit_pointer(name, out)
