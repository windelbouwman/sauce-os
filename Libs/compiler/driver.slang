"""Main compilation driver."""

import ast
import bc
from fs import Path
from errors import CompilationError, new_error_with_filename
from parsing import parse_source, ParseError, parse_module_from_text
from namebinding import bind_names
from pass3 import resolve_newops
from codegen import CodegenOptions
from typechecking import type_check
from typedb import store_symbol_table, load_symbol_table
from utils import panic, assert
from logging import log_error, log_info, log_trace, log_debug
from ir_gen import gen_bytecode
from pygenerator import gen_python
from basepass import IdGen
from transforms import transform, TransformOptions
from builtins import get_rt_module
from listtype import List
from location import location_default
from optiontype import option_unwrap, Option, option_unwrap_or
from opt import optimize_sil
from hashmap import HashMap, new_hashmap_str
from graphlib import DiGraph, topological_sort
from c_gen import gen_c_code
from c_gen_v2 import gen_c_code_v2
from wasm_gen import gen_webassembly_text, gen_webassembly_binary
from riscv_gen import gen_riscv
from bc_to_sil import to_sil
from dbginfo import DbgInfo
from x86_gen import gen_x86
from slang_gen import gen_slang
from vm import run_bytecode
from profiling import Profiler
from report import Report

pub struct CompilationOptions:
	dump_ast: bool
	backend: Backend
	add_imports: List[str]
	output_filename: Option[str]
	gen_export: Option[str]
	verbosity: int
	optimization_level: int
	runtime: bool
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
		runtime: true
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
		for module in imported_modules:
			builder.add_module(module)

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

	let module_set = builder.do_transform()

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
			gen_python(module_set, generate_runtime: options.runtime, output_filename: options.output_filename)
		Slang:
			gen_slang(module_set, output_filename: options.output_filename)
		Bytecode:
			let program = gen_bytecode(module_set, debug: builder.m_debug)
			if options.run_code:
				if options.verbosity > 1:
					bc.print_bc_program(program)
				log_info("Now running code")
				run_bytecode(program, entry_function: "main2")
			else:
				bc.print_bc_program_to_file(program, filename: options.output_filename)
		C:
			# Generate C-code via bytecode:
			let program = gen_bytecode(module_set, debug: builder.m_debug)
			if options.verbosity > 1:
				bc.print_bc_program(program)
			gen_c_code(program, output_filename: options.output_filename)
		C2:
			# Generate C-code straight from AST:
			gen_c_code_v2(module_set, output_filename: options.output_filename)
		WebAssembly(binary):
			if binary:
				let filename = option_unwrap_or(option: options.output_filename, default: "out.wasm")
				gen_webassembly_binary(module_set, typectx: builder.m_typectx, filename)
			else:
				gen_webassembly_text(module_set, typectx: builder.m_typectx, output_filename: options.output_filename)
		Riscv:
			let bc_program = gen_bytecode(module_set, debug: builder.m_debug)
			let sil_program = to_sil(program: bc_program, bits: 32)
			optimize_sil(program: sil_program, level: options.optimization_level)
			gen_riscv(program: sil_program, options: cgen_options)
		X86:
			let bc_program = gen_bytecode(module_set, debug: builder.m_debug)
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
	builder.add_module(module: rt_module)
	builder

class Builder:
	pub var options: CompilationOptions
	pub var m_profiler: Profiler = Profiler()
	pub var m_id_gen: IdGen = IdGen()
	var m_modules: List[ast.ModuleDef] = List()
	var m_module_map: HashMap[str,ast.ModuleDef] = new_hashmap_str()
	pub var m_typectx: ast.TypeContext
	var m_top_module: ast.ModuleDef = ast.new_empty_module(name: "toplevel", location: location_default())
	var m_rt_module: ast.ModuleDef
	pub var m_debug: Option[DbgInfo]

	pub fn add_module(module: ast.ModuleDef):
		m_modules.append(module)
		m_module_map.insert(key: module.name, value: module)
		m_top_module.add_module(module)

	pub fn parse_module(path: Path) except ParseError:
		let program = parse_source(path, id_gen: m_id_gen, typectx: m_typectx, debug: m_debug)
		log_trace("Parsed module: {program.name}")
		if options.dump_ast:
			ast.print_ast(module: program)
		add_module(module: program)

	pub fn do_transform() -> ast.ModuleSet except CompilationError:
		"""Perform type checking and transformation on the added modules"""
		topo_sort(modules: m_modules)
		let module_set = ast.ModuleSet(modules: m_modules)

		m_profiler.enter(name: "binding")
		bind_names(module: m_top_module, typectx: m_typectx, module_map: m_module_map)
		resolve_newops(module: m_top_module, id_gen: m_id_gen)
		m_profiler.leave()

		if options.dump_ast:
			ast.print_ast2(module_set)

		m_profiler.enter(name: "typecheck")
		type_check(module: m_top_module, typectx: m_typectx, display_warnings: true)
		m_profiler.leave()

		m_profiler.enter(name: "export")
		case options.gen_export:
			Some(filename):
				store_symbol_table(module_set, filename)
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
		transform(module_set, typectx: m_typectx, id_gen: m_id_gen, rt_module: m_rt_module, options: transform_options)
		m_profiler.leave()

		if options.dump_ast:
			ast.print_ast2(module_set)

		m_profiler.enter(name: "typecheck")
		type_check(module: m_top_module, typectx: m_typectx, display_warnings: false)
		m_profiler.leave()

		if options.dump_ast:
			ast.print_ast2(module_set)
		module_set

fn topo_sort(modules: List[ast.ModuleDef]):
	# Sort modules (in-place) based on which module import the other one
	# TBD: implicitly, all modules depend upon the 'rt' module. Add this as edge?
	let g: DiGraph = DiGraph()
	let mapping: HashMap[str,ast.ModuleDef] = new_hashmap_str()
	for m in modules:
		g.add_node(m.name)
		mapping.insert(key: m.name, value: m)
		for imp in m.imports:
			g.add_edge(src: m.name, dst: imp.modname)

	# For displaying dependencies:
	#for n1 in g.nodes:
	#    for n2 in option_unwrap(g.pred.get(key: n1)):
	#        print("{n1} is needed by {n2}")

	modules.clear()
	case topological_sort(g):
		Some(names):
			log_debug("topo sorted modules:")
			names = names.reversed()
			for name in names:
				log_debug("-: {name}")
				if mapping.contains(key: name):
					modules.append(option_unwrap(mapping.pop(key: name)))
			assert(condition: mapping.is_empty(), message: "Mapping must be empty")
		None:
			panic("dependency cycle!")

pub fn slang_to_python(code: str, output_filename: str):
	"""Compile given code to python string"""
	let options = default_compile_options()
	let builder = new_builder(options)

	let filename = "noname.slang"
	try:
		let program = parse_module_from_text(source: code, filename, id_gen: builder.m_id_gen, typectx: builder.m_typectx, debug: builder.m_debug)
		log_trace("Parsed module: {program.name}")
		builder.add_module(module: program)
	except (e: ParseError):
		log_error("Parse error")
		return

	try:
		let module_set = builder.do_transform()
		# gen_python(module_set, generate_runtime: false, output_filename: Option.Some(output_filename))
		gen_webassembly_text(module_set, typectx: builder.m_typectx, output_filename: Option.Some(output_filename))
	except (compile_error: CompilationError):
		log_error("Compile error")
		return
