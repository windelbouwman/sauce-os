module main
"""SlangC compiler"""

from std import print, get_n_args, get_arg
from base.logging import log_info, log_error, set_log_level
from base.optiontype import Option
from base.fs import lexical_sort_paths, new_path, Path
from base.listtype import List
from base.strlib import lexical_sort
from compiler.errors import display_error, CompilationError
from compiler.driver import compile, CompilationOptions, Backend, default_compile_options


pub fn main() -> int:
	var sources: List[Path] = List()
	let options = default_compile_options()

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
		elif argument == "--backend-c-v2":
			options.backend = Backend.C2()
		elif argument == "--backend-c":
			options.backend = Backend.C()
		elif argument == "--backend-py":
			options.backend = Backend.Python()
		elif argument == "--backend-null":
			options.backend = Backend.Null()
		elif argument == "--backend-sil":
			options.backend = Backend.Sil()
		elif argument == "--backend-riscv":
			options.backend = Backend.Riscv()
		elif argument == "--backend-x86":
			options.backend = Backend.X86()
		elif argument == "--backend-wasm":
			options.backend = Backend.WebAssembly(binary: true)
		elif argument == "--backend-wat":
			options.backend = Backend.WebAssembly(binary: false)
		elif argument == "--backend-slang":
			options.backend = Backend.Slang()
		elif argument == "--run":
			options.run_code = true
		elif argument == "--optimize":
			options.optimization_level = 2
		elif argument == "--no-optimize":
			options.optimization_level = 0
		elif argument == "--debug":
			options.debug = true
		elif argument == "--time-trace":
			options.time_trace = true
		elif argument == "--report":
			options.report = true
		else:
			# Assume source file
			sources.append(new_path(filename: argument))
		i += 1

	set_log_level(level: options.verbosity)

	if sources.is_empty():
		log_error("No input")
		return 2

	sources = lexical_sort_paths(sources)

	try:
		compile(sources, options)
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
	print("    --backend-c-v2  : Spit out C code (version 2)")
	print("    --backend-wasm  : Spit out WebAssembly")
	print("    --backend-wat   : Spit out WebAssembly - text format")
	print("    --backend-sil   : Spit out SIL (slang-intermediate-language)")
	print("    --backend-riscv : Spit out RiscV code")
	print("    --backend-null  : Skip code generation")
	print("    --backend-slang : Spit out slang")
	print("    --backend-x86   : Spit out x86 code")
	print("    --report        : Create compilation report")
	print("    --time-trace    : Create compilation time-trace report")
	print("    --run : Run code!")
	print("")
	print("Multiple source files can be passed")
