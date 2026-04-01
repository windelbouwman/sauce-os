module compiler.driver
"""Main compilation driver."""

import ast
import bc
from base.fs import Path
from errors import CompilationError, new_error_with_filename
from parsing.parsing import parse_source, ParseError, parse_module_from_text
from namebinding import bind_names
from pass3 import resolve_newops
from backend.codegen import CodegenOptions
from typechecking import type_check
from typedb import store_symbol_table, load_symbol_table
from base.utils import panic, assert
from base.logging import log_error, log_info, log_trace, log_debug
from ir_gen import gen_bytecode
from pygenerator import gen_python
from basepass import IdGen
from transforms import transform, TransformOptions
from builtins import get_rt_module
from base.listtype import List, list1
from location import location_default
from base.optiontype import option_unwrap, Option, option_unwrap_or
from opt import optimize_sil
from base.hashmap import HashMap, new_hashmap_str
from base.graphlib import DiGraph, topological_sort
from c_gen import gen_c_code
from c_gen_v2 import gen_c_code_v2
from wasm_gen import gen_webassembly_text, gen_webassembly_binary
from riscv_gen import gen_riscv
from bc_to_sil import to_sil
from dbginfo import DbgInfo
from x86_gen import gen_x86
from slang_gen import gen_slang
from vm import run_bytecode
from base.profiling import Profiler
from report import Report

pub struct CompilationOptions:
	dump_ast: bool
	backend: Backend
	add_imports: List[str]
	output_filename: Option[str]
	gen_export: Option[str]
	verbosity: int
	optimization_level: int
	run_code: bool
	time_trace: bool
	report: bool
	debug: bool

pub enum Backend:
	Bytecode
	C
	C2
	Python
	Slang
	WebAssembly(binary: bool)
	Null
	Riscv
	X86

pub fn default_compile_options() -> CompilationOptions:
	CompilationOptions:
		dump_ast: false
		backend: Backend.Python()
		add_imports: List()
		output_filename: Option.None()
		gen_export: Option.None()
		verbosity: 0
		optimization_level: 1
		run_code: false
		time_trace: false
		report: false
		debug: false

pub fn compile(sources: List[Path], options: CompilationOptions) except CompilationError:
	"""Batch compile"""
	let builder = new_builder(options)
	builder.m_profiler.enter(name: "compile")

	for filename in options.add_imports:
		let imported_modules = load_symbol_table(filename, typectx: builder.m_typectx)
		for module_def in imported_modules:
			builder.add_module(module_def)

	builder.m_profiler.enter(name: "parsing")
	for path in sources:
		log_info("Parsing: {path}")
		builder.m_profiler.enter(name: "parse")
		try:
			builder.parse_module(path)
		except (e: ParseError):
			raise new_error_with_filename(filename: path.filename, location: e.location, message: e.message)
		builder.m_profiler.leave()
	builder.m_profiler.leave()

	builder.do_transform()

	builder.m_profiler.enter(name: "backend")
	let report = Report()
	report.set_enabled(options.report)
	let cgen_options = CodegenOptions:
		filename: options.output_filename
		report: report
		profiler: builder.m_profiler
		debug: builder.m_debug
	case options.backend:
		Null:  # no-op backend.
			pass
		Python:
			gen_python(module_defs: builder.m_modules, output_filename: options.output_filename)
		Slang:
			gen_slang(module_defs: builder.m_modules, output_filename: options.output_filename)
		Bytecode:
			let program = gen_bytecode(module_defs: builder.m_modules, debug: builder.m_debug)
			if options.run_code:
				if options.verbosity > 1:
					bc.print_bc_program(program)
				log_info("Now running code")
				run_bytecode(program, entry_function: "main_main")
			else:
				bc.print_bc_program_to_file(program, filename: options.output_filename)
		C:
			# Generate C-code via bytecode:
			let program = gen_bytecode(module_defs: builder.m_modules, debug: builder.m_debug)
			if options.verbosity > 1:
				bc.print_bc_program(program)
			gen_c_code(program, output_filename: options.output_filename)
		C2:
			# Generate C-code straight from AST:
			gen_c_code_v2(module_defs: builder.m_modules, output_filename: options.output_filename)
		WebAssembly(binary):
			if binary:
				let filename = option_unwrap_or(option: options.output_filename, default: "out.wasm")
				gen_webassembly_binary(module_defs: builder.m_modules, typectx: builder.m_typectx, filename)
			else:
				gen_webassembly_text(module_defs: builder.m_modules, typectx: builder.m_typectx, output_filename: options.output_filename)
		Riscv:
			let bc_program = gen_bytecode(module_defs: builder.m_modules, debug: builder.m_debug)
			let sil_program = to_sil(program: bc_program, bits: 32)
			optimize_sil(program: sil_program, level: options.optimization_level)
			gen_riscv(program: sil_program, options: cgen_options)
		X86:
			let bc_program = gen_bytecode(module_defs: builder.m_modules, debug: builder.m_debug)
			let sil_program = to_sil(program: bc_program, bits: 64)
			optimize_sil(program: sil_program, level: options.optimization_level)
			gen_x86(program: sil_program, options: cgen_options)
	report.set_enabled(false)
	builder.m_profiler.leave()

	builder.m_profiler.leave()
	if options.time_trace:
		builder.m_profiler.write_json(filename: "trace.json")

fn new_builder(options: CompilationOptions) -> Builder:
	let typectx = ast.make_typectx()
	let rt_module = get_rt_module(typectx)
	let debug = Option.Some(DbgInfo()) if options.debug else Option.None()
	let builder = Builder(options, m_typectx: typectx, m_rt_module: rt_module, m_debug: debug)
	builder.add_module(module_def: rt_module)
	builder

class Builder:
	pub var options: CompilationOptions
	pub var m_profiler: Profiler = Profiler()
	pub var m_id_gen: IdGen = IdGen()
	pub var m_modules: List[ast.ModuleDef] = List()
	pub var m_typectx: ast.TypeContext
	var m_rt_module: ast.ModuleDef
	pub var m_debug: Option[DbgInfo]

	pub fn add_module(module_def: ast.ModuleDef):
		m_modules.append(module_def)

	pub fn parse_module(path: Path) except ParseError:
		let program = parse_source(path, id_gen: m_id_gen, typectx: m_typectx, debug: m_debug)
		log_trace("Parsed module: {program.get_name()}")
		if options.dump_ast:
			ast.print_ast(module_def: program)
		add_module(module_def: program)

	pub fn do_transform() except CompilationError:
		"""Perform type checking and transformation on the added modules"""
		m_profiler.enter(name: "binding")
		bind_names(module_defs: m_modules, typectx: m_typectx)
		resolve_newops(module_defs: m_modules, id_gen: m_id_gen)
		m_profiler.leave()

		if options.dump_ast:
			ast.print_ast2(module_defs: m_modules)

		m_profiler.enter(name: "typecheck")
		type_check(module_defs: m_modules, typectx: m_typectx, display_warnings: true)
		m_profiler.leave()

		m_profiler.enter(name: "export")
		case options.gen_export:
			Some(filename):
				store_symbol_table(module_defs: m_modules, filename)
			None:
				pass
		m_profiler.leave()

		let transform_options = TransformOptions:
			keep_switch: false
		# TODO: When keeping switch statements, we get a break in a break
		# case options.backend:
		# 	C2:
		# 		transform_options.keep_switch = true
		# else:
		# 	pass

		m_profiler.enter(name: "transform")
		transform(module_defs: m_modules, typectx: m_typectx, id_gen: m_id_gen, rt_module: m_rt_module, options: transform_options)
		m_profiler.leave()

		if options.dump_ast:
			ast.print_ast2(module_defs: m_modules)

		m_profiler.enter(name: "typecheck")
		type_check(module_defs: m_modules, typectx: m_typectx, display_warnings: false)
		m_profiler.leave()

		if options.dump_ast:
			ast.print_ast2(module_defs: m_modules)
