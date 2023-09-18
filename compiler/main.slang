
from std import print, get_n_args, get_arg
import ast
import bc
from errors import display_error, CompilationError
from parsing import parse_source
from namebinding import bind_names
from pass3 import resolve_newops
from typechecking import type_check
from utils import log_info, log_error, log_trace, panic, assert
from ir_gen import gen_bytecode
from pygenerator import gen_python
from basepass import IdGen
from transforms import transform
from builtins import get_std_module
from datatypes import List, Dictionary, Result, option_unwrap
from strlib import String, new_string, string_compare
from graphlib import DiGraph, topological_sort
from sorting import sort_list


fn main() -> int:
    let filenames: List[String] = List()

    # Argument processing
    let n = get_n_args()
    let i = 0
    while i < n:
        let filename = get_arg(i)
        filenames.append(new_string(filename))
        i += 1
    
    # Sort filenames lexicographical
    filenames = sort_list(filenames, cmp: string_compare)

    let options = CompilationOptions(dump_ast: false)
    try:
        let prog = compile(filenames, options)
        log_info("OK")
        return 0
    except (error: CompilationError):
        log_error("HORROR")
        display_error(error)
        return 1

struct CompilationOptions:
    dump_ast: bool

fn compile(filenames: List[String], options: CompilationOptions) -> bc.Program except CompilationError:
    let id_gen = IdGen()
    let module_map: Dictionary[ast.Module] = Dictionary()
    let std_module = get_std_module()
    module_map.insert(key: "std", value: std_module)

    let modules: List[ast.Module] = List()
    for filename in filenames:
        log_info("Parsing: {filename.value}")

        let program = parse_source(filename, id_gen)
        log_trace("Parsed module: {program.name}")
        # ast.print_ast(program)
        modules.append(program)
        module_map.insert(key: program.name, value: program)
    
    topo_sort(modules)

    for module in modules:
        bind_names(module, module_map)
        resolve_newops(module, id_gen)
    
    for module3 in modules:
        if options.dump_ast:
            ast.print_ast(module: module3)
        type_check(module: module3)
    
    for module4 in modules:
        transform(module: module4, id_gen, std_module)
        if options.dump_ast:
            ast.print_ast(module: module4)
        type_check(module: module4)

    for module5 in modules:
        if options.dump_ast:
            ast.print_ast(module: module5)

    # TODO!
    for module6 in modules:
        # let prog = gen_bytecode(module2)
        #log_info("generating bytecode: {module2.name}")
        gen_python(prog: module6)
        # pass

    let prog = bc.new_program()
    return prog

fn topo_sort(modules: List[ast.Module]):
    # Sort modules (in-place) based on which module import the other one
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
