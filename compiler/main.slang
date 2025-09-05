
from std import print, get_n_args, get_arg
import ast
import bc
from errors import display_error, CompilationError, new_error_with_filename
from parsing import parse_source, ParseError
from namebinding import bind_names
from pass3 import resolve_newops
from typechecking import type_check
from typedb import store_symbol_table, load_symbol_table
from utils import log_info, log_error, log_trace, panic, assert, set_log_level
from ir_gen import gen_bytecode
from pygenerator import gen_python
from basepass import IdGen
from transforms import transform, TransformOptions
from builtins import get_rt_module
from listtype import List
from location import location_default
from optiontype import option_unwrap, Option
from hashmap import HashMap, new_hashmap_str
from strlib import lexical_sort
from graphlib import DiGraph, topological_sort
from c_gen import gen_c_code
from c_gen_v2 import gen_c_code_v2
from wasm_gen import gen_webassembly
from riscv_gen import gen_riscv
from bc_to_sil import to_sil
from x86_gen import gen_x86
from slang_gen import gen_slang
from vm import run_bytecode


pub fn main() -> int:
	var filenames: List[str] = List()

	let options = CompilationOptions:
		dump_ast: false
		backend: Backend.Python()
		add_imports: List()
		output_filename: Option.None()
		gen_export: Option.None()
		verbosity: 0
		runtime: true
		run_code: false

	# Argument processing
	let n = get_n_args()
	var i = 0
	while i < n:
		let argument = get_arg(arg: i)
		if argument == "-d":
			options.dump_ast = true
		elif argument == "-h" or argument == "--help":
			print_usage()
			return 0
		elif argument == "--version":
			print("Latest")
			return 0
		elif argument == "-o" or argument == "--output":
			i += 1
			if i < n:
				options.output_filename = Option.Some(get_arg(arg: i))
			else:
				print("Expect argument to -o")
		elif argument == "-v":
			options.verbosity += 1
		elif argument == "--add-import":
			i += 1
			if i < n:
				options.add_imports.append(get_arg(arg: i))
			else:
				print("Expect argument to --add-import")
		elif argument == "--gen-export":
			i += 1
			if i < n:
				options.gen_export = Option.Some(get_arg(arg: i))
			else:
				print("Expect argument to --gen-export")
		elif argument == "--backend-bc":
			options.backend = Backend.Bytecode()
		elif argument == "--backend-c":
			options.backend = Backend.C()
		elif argument == "--backend-c-v2":
			options.backend = Backend.C2()
		elif argument == "--backend-py":
			options.backend = Backend.Python()
		elif argument == "--backend-null":
			options.backend = Backend.Null()
		elif argument == "--backend-riscv":
			options.backend = Backend.Riscv()
		elif argument == "--backend-x86":
			options.backend = Backend.X86()
		elif argument == "-rt":
			options.runtime = false
		elif argument == "--backend-wasm":
			options.backend = Backend.WebAssembly()
		elif argument == "--backend-slang":
			options.backend = Backend.Slang()
		elif argument == "--run":
			options.run_code = true
		else:
			# Assume source file
			filenames.append(argument)
		i += 1

	set_log_level(level: options.verbosity)

	if filenames.is_empty():
		log_error("No input")
		return 2

	filenames = lexical_sort(filenames)

	try:
		compile(filenames, options)
		log_info("OK")
		return 0
	except (error: CompilationError):
		log_error("Errors found during compilation")
		display_error(error)
		return 1
	0

fn print_usage():
	print("Slang compiler written in slang!")
	print("")
	print("Usage:")
	print("$ compiler.exe [-d] [-v] file1.slang file2.slang ..")
	print("    -d              : dump AST between compilation phases")
	print("    -v              : Increase verbosity")
	print("    --version       : Print version")
	print("    -o --output     : Write output to given filename")
	print("    -h --help       : display usage information")
	print("    --add-import filename.json   : Additional importable modules in JSON")
	print("    --gen-export filename.json   : Create a JSON file for later importing")
	print("    --backend-bc    : Spit out bytecode")
	print("    --backend-py    : Spit out python code")
	print("    --backend-c     : Spit out C code")
	print("    --backend-wasm  : Spit out WebAssembly")
	print("    --backend-riscv : Spit out RiscV code")
	print("    --backend-null  : Skip code generation")
	print("    --backend-slang : Spit out slang")
	print("    --backend-x86   : Spit out x86 code")
	print("    -rt : Skip runtime?")
	print("    --run : Run code!")
	print("")
	print("Multiple source files can be passed")

struct CompilationOptions:
	dump_ast: bool
	backend: Backend
	add_imports: List[str]
	output_filename: Option[str]
	gen_export: Option[str]
	verbosity: int
	runtime: bool
	run_code: bool

enum Backend:
	Bytecode
	C
	C2
	Python
	Slang
	WebAssembly
	Null
	Riscv
	X86

fn compile(filenames: List[str], options: CompilationOptions) except CompilationError:
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

	for filename in filenames:
		log_info("Parsing: {filename}")

		try:
			let program = parse_source(filename, id_gen)
			log_trace("Parsed module: {program.name}")
			if options.dump_ast:
				ast.print_ast(module: program)
			modules.append(program)
			module_map.insert(key: program.name, value: program)
			top_module.add_module(program)
		except (e: ParseError):
			raise new_error_with_filename(filename, location: e.location, message: e.message)

	topo_sort(modules)
	let module_set = ast.ModuleSet(modules)

	bind_names(module: top_module, module_map)
	resolve_newops(module: top_module, id_gen)

	if options.dump_ast:
		ast.print_ast2(module_set)

	type_check(module: top_module, display_warnings: true)

	case options.gen_export:
		Some(filename):
			store_symbol_table(module_set, filename)
		None:
			pass

	let transform_options = TransformOptions:
		keep_switch: false
	# TODO: When keeping switch statements, we get a break in a break
	# case options.backend:
	# 	C2:
	# 		transform_options.keep_switch = true
	# else:
	# 	pass

	transform(module_set, id_gen, rt_module, options: transform_options)

	if options.dump_ast:
		ast.print_ast2(module_set)

	type_check(module: top_module, display_warnings: false)

	if options.dump_ast:
		ast.print_ast2(module_set)

	case options.backend:
		Null:  # no-op backend.
			pass
		Python:
			gen_python(module_set, generate_runtime: options.runtime, output_filename: options.output_filename)
		Slang:
			gen_slang(module_set, output_filename: options.output_filename)
		Bytecode:
			let program = gen_bytecode(module_set)
			if options.run_code:
				if options.verbosity > 1:
					bc.print_bc_program(program)
				log_info("Now running code")
				run_bytecode(program, entry_function: "main2")
			else:
				bc.print_bc_program_to_file(program, filename: options.output_filename)
		C:
			# Generate C-code via bytecode:
			let program = gen_bytecode(module_set)
			if options.verbosity > 1:
				bc.print_bc_program(program)
			gen_c_code(program, output_filename: options.output_filename)
		C2:
			# Generate C-code straight from AST:
			gen_c_code_v2(module_set, output_filename: options.output_filename)
		WebAssembly:
			gen_webassembly(module_set)
		Riscv:
			let program = gen_bytecode(module_set)
			gen_riscv(program: to_sil(program))
		X86:
			let program = gen_bytecode(module_set)
			gen_x86(program: to_sil(program), filename: options.output_filename)

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
			log_info("topo sorted modules:")
			names = names.reversed()
			for name in names:
				log_info("-: {name}")
				if mapping.contains(key: name):
					modules.append(option_unwrap(mapping.pop(key: name)))
			assert(condition: mapping.is_empty(), message: "Mapping must be empty")
		None:
			panic("dependency cycle!")
