
from std import print, get_n_args, get_arg
import ast
import bc
from errors import display_error, CompilationError
from parsing import parse_source
from namebinding import bind_names
from pass3 import resolve_newops
from typechecking import type_check_modules
from utils import log_info, log_error, log_trace, panic, assert, set_log_level
from ir_gen import gen_bytecode
from pygenerator import gen_python
from basepass import IdGen
from transforms import transform
from builtins import get_rt_module
from datatypes import List, Dictionary, Result, option_unwrap, Option
from strlib import string_compare
from graphlib import DiGraph, topological_sort
from sorting import sort_list
from c_gen import gen_c_code
from c_gen_v2 import gen_c_code_v2
from wasm_gen import gen_webassembly
from vm import run_bytecode


fn main() -> int:
    let filenames: List[str] = List()

    let options = CompilationOptions:
        dump_ast: false
        backend: Backend.Python()
        output_filename: Option.None()
        verbosity: 0
        runtime: true
        run_code: false

    # Argument processing
    let n = get_n_args()
    let i = 0
    while i < n:
        let argument = get_arg(i)
        if argument == "-d":
            options.dump_ast = true
        elif argument == "-h":
            print_usage()
            return 0
        elif argument == "-o":
            i += 1
            if i < n:
                options.output_filename = Option.Some(get_arg(i))
            else:
                print("Expect argument to -o")
        elif argument == "-v":
            options.verbosity += 1
        elif argument == "--backend-bc":
            options.backend = Backend.Bytecode()
        elif argument == "--backend-c":
            options.backend = Backend.C()
        elif argument == "--backend-py":
            options.backend = Backend.Python()
        elif argument == "--backend-null":
            options.backend = Backend.Null()
        elif argument == "-rt":
            options.runtime = false
        elif argument == "--backend-wasm":
            options.backend = Backend.WebAssembly()
        elif argument == "--run":
            options.run_code = true
        else:
            # Assume source file
            filenames.append(argument)
        i += 1
    
    set_log_level(level: options.verbosity)
    # Sort filenames lexicographical
    filenames = sort_list(filenames, cmp: string_compare)
    
    try:
        compile(filenames, options)
        log_info("OK")
        return 0
    except (error: CompilationError):
        log_error("Errors found during compilation")
        display_error(error)
        return 1

fn print_usage():
    print("Slang compiler written in slang!")
    print("")
    print("Usage:")
    print("$ compiler.exe [-d] file1.slang file2.slang ..")
    print("    -d : dump AST between compilation phases")
    print("    -v : Increase verbosity")
    print("    -o : Write output to given filename")
    print("    -h : display usage information")
    print("    --backend-bc    : Spit out bytecode")
    print("    --backend-py    : Spit out python code")
    print("    --backend-c     : Spit out C code")
    print("    --backend-wasm  : Spit out WebAssembly")
    print("    -rt : Skip runtime?")
    print("    --run : Run code!")
    print("")
    print("Multiple source files can be passed")

struct CompilationOptions:
    dump_ast: bool
    backend: Backend
    output_filename: Option[str]
    verbosity: int
    runtime: bool
    run_code: bool

enum Backend:
    Bytecode
    C
    Python
    WebAssembly
    Null

fn compile(filenames: List[str], options: CompilationOptions) except CompilationError:
    let id_gen = IdGen()
    let module_map: Dictionary[ast.Module] = Dictionary()
    let rt_module = get_rt_module()
    module_map.insert(key: "rt", value: rt_module)

    let modules: List[ast.Module] = List()
    modules.append(rt_module)
    for filename in filenames:
        log_info("Parsing: {filename}")

        let program = parse_source(filename, id_gen)
        log_trace("Parsed module: {program.name}")
        if options.dump_ast:
            ast.print_ast(module: program)
        modules.append(program)
        module_map.insert(key: program.name, value: program)
    
    topo_sort(modules)
    let module_set = ast.ModuleSet(modules)

    for module in modules:
        bind_names(module, module_map)
        resolve_newops(module, id_gen)
    
    if options.dump_ast:
        ast.print_ast2(module_set)

    type_check_modules(module_set)
    transform(module_set, id_gen, rt_module)

    if options.dump_ast:
        ast.print_ast2(module_set)

    type_check_modules(module_set)

    if options.dump_ast:
        ast.print_ast2(module_set)
 
    case options.backend:
        Null:  # no-op backend.
            pass
        Python:
            gen_python(module_set, generate_runtime: options.runtime, output_filename: options.output_filename)
        Bytecode:
            let program = gen_bytecode(module_set)
            if options.run_code:
                if options.verbosity > 0:
                    bc.print_bc_program(program)
                log_info("Now running code")
                run_bytecode(program, entry_function: "main")
            else:
                bc.print_bc_program(program)
        C:
            let use_v2 = true
            if use_v2:
                # Generate C-code straight from AST:
                gen_c_code_v2(module_set, output_filename: options.output_filename)
            else:
                # Generate C-code via bytecode:
                let program = gen_bytecode(module_set)
                if options.verbosity > 0:
                    bc.print_bc_program(program)
                gen_c_code(program)
        WebAssembly:
            gen_webassembly(module_set)

fn topo_sort(modules: List[ast.Module]):
    # Sort modules (in-place) based on which module import the other one
    # TBD: implicitly, all modules depend upon the 'rt' module. Add this as edge?
    let g: DiGraph = DiGraph()
    let mapping: Dictionary[ast.Module] = Dictionary()
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
