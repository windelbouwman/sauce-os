"""
Main compilation driver.

"""

import ast
import bc
from errors import CompilationError, new_error_with_filename
from parsing import parse_source, ParseError
from namebinding import bind_names
from pass3 import resolve_newops
from codegen import CodegenOptions
from typechecking import type_check
from typedb import store_symbol_table, load_symbol_table
from utils import panic, assert
from logging import log_info, log_trace, log_debug
from ir_gen import gen_bytecode
from pygenerator import gen_python
from basepass import IdGen
from transforms import transform, TransformOptions
from builtins import get_rt_module
from listtype import List
from location import location_default
from optiontype import option_unwrap, Option
from hashmap import HashMap, new_hashmap_str
from graphlib import DiGraph, topological_sort
from c_gen import gen_c_code
from c_gen_v2 import gen_c_code_v2
from wasm_gen import gen_webassembly
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
	WebAssembly
	Null
	Riscv
	X86

pub fn compile(filenames: List[str], options: CompilationOptions) except CompilationError:
	""" Batch compile """
	let p = Profiler()
	p.enter(name: "compile")
	let id_gen = IdGen()
	let top_module = ast.new_empty_module(name: "toplevel", location: location_default())
	let modules: List[ast.ModuleDef] = List()
	let module_map: HashMap[str,ast.ModuleDef] = new_hashmap_str()

	let rt_module = get_rt_module()
	modules.append(rt_module)
	module_map.insert(key: rt_module.name, value: rt_module)
	top_module.add_module(rt_module)

	for filename in options.add_imports:
		let imported_modules = load_symbol_table(filename)
		for module in imported_modules:
			modules.append(module)
			module_map.insert(key: module.name, value: module)
			top_module.add_module(module)

	let debug = Option.Some(DbgInfo()) if options.debug else Option.None()

	p.enter(name: "parsing")
	for filename in filenames:
		log_info("Parsing: {filename}")
		p.enter(name: "parse")

		try:
			let program = parse_source(filename, id_gen, debug)
			log_trace("Parsed module: {program.name}")
			if options.dump_ast:
				ast.print_ast(module: program)
			modules.append(program)
			module_map.insert(key: program.name, value: program)
			top_module.add_module(program)
		except (e: ParseError):
			raise new_error_with_filename(filename, location: e.location, message: e.message)
		p.leave()
	p.leave()

	topo_sort(modules)
	let module_set = ast.ModuleSet(modules)

	p.enter(name: "binding")
	bind_names(module: top_module, module_map)
	resolve_newops(module: top_module, id_gen)
	p.leave()

	if options.dump_ast:
		ast.print_ast2(module_set)

	p.enter(name: "typecheck")
	type_check(module: top_module, display_warnings: true)
	p.leave()

	p.enter(name: "export")
	case options.gen_export:
		Some(filename):
			store_symbol_table(module_set, filename)
		None:
			pass
	p.leave()

	let transform_options = TransformOptions:
		keep_switch: false
	# TODO: When keeping switch statements, we get a break in a break
	# case options.backend:
	# 	C2:
	# 		transform_options.keep_switch = true
	# else:
	# 	pass

	p.enter(name: "transform")
	transform(module_set, id_gen, rt_module, options: transform_options)
	p.leave()

	if options.dump_ast:
		ast.print_ast2(module_set)

	p.enter(name: "typecheck")
	type_check(module: top_module, display_warnings: false)
	p.leave()

	if options.dump_ast:
		ast.print_ast2(module_set)

	p.enter(name: "backend")
	let report = Report()
	report.set_enabled(options.report)
	let cgen_options = CodegenOptions:
		filename: options.output_filename
		report: report
		debug
	case options.backend:
		Null:  # no-op backend.
			pass
		Python:
			gen_python(module_set, generate_runtime: options.runtime, output_filename: options.output_filename)
		Slang:
			gen_slang(module_set, output_filename: options.output_filename)
		Bytecode:
			let program = gen_bytecode(module_set, debug)
			if options.run_code:
				if options.verbosity > 1:
					bc.print_bc_program(program)
				log_info("Now running code")
				run_bytecode(program, entry_function: "main2")
			else:
				bc.print_bc_program_to_file(program, filename: options.output_filename)
		C:
			# Generate C-code via bytecode:
			let program = gen_bytecode(module_set, debug)
			if options.verbosity > 1:
				bc.print_bc_program(program)
			gen_c_code(program, output_filename: options.output_filename)
		C2:
			# Generate C-code straight from AST:
			gen_c_code_v2(module_set, output_filename: options.output_filename)
		WebAssembly:
			gen_webassembly(module_set)
		Riscv:
			let program = gen_bytecode(module_set, debug)
			gen_riscv(program: to_sil(program), options: cgen_options)
		X86:
			let program = gen_bytecode(module_set, debug)
			gen_x86(program: to_sil(program), options: cgen_options)
	report.set_enabled(false)
	p.leave()

	p.leave()
	if options.time_trace:
		p.write_json(filename: "trace.json")

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
