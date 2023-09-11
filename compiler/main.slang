
from std import print
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
from transforms import transform
from builtins import get_std_module
from datatypes import List, Dictionary, Result, option_unwrap
from strlib import String, new_string, string_compare
from graphlib import DiGraph, topological_sort
from sorting import sort_list


fn main() -> int:
    # let filename = "dummy.slang"
    let filenames: List[String] = List()

    # Manually sorted list of compiler sources:
    if false:
        filenames.append(new_string("compiler/location.slang"))
        filenames.append(new_string("compiler/utils.slang"))
        filenames.append(new_string("compiler/token.slang"))
        filenames.append(new_string("compiler/datatypes.slang"))
        filenames.append(new_string("compiler/strlib.slang"))
        filenames.append(new_string("compiler/bc.slang"))
        filenames.append(new_string("compiler/errors.slang"))
        filenames.append(new_string("compiler/lexer.slang"))
        filenames.append(new_string("compiler/sorting.slang"))
        filenames.append(new_string("compiler/graphlib.slang"))
        filenames.append(new_string("compiler/ast.slang"))
        filenames.append(new_string("compiler/parsing.slang"))
        filenames.append(new_string("compiler/namebinding.slang"))
        filenames.append(new_string("compiler/builtins.slang"))
        filenames.append(new_string("compiler/pass3.slang"))
        filenames.append(new_string("compiler/typechecking.slang"))
        filenames.append(new_string("compiler/transforms.slang"))
        filenames.append(new_string("compiler/pygenerator.slang"))
        filenames.append(new_string("compiler/ir_gen.slang"))
        filenames.append(new_string("compiler/main.slang"))
        filenames.append(new_string("compiler/vm.slang"))
    else:

        #filenames.append(new_string("examples/hello-world.slang"))
        # filenames.append(new_string("examples/callings.slang"))
        filenames.append(new_string("examples/classy.slang"))
        #filenames.append(new_string("examples/expressions.slang"))
        # filenames.append(new_string("examples/mandel.slang"))
        # filenames.append(new_string("examples/structs-passing.slang"))
        # filenames.append(new_string("examples/loops.slang"))
        # filenames.append(new_string("examples/exceptionally.slang"))
    
    # Sort filenames lexicographical
    filenames = sort_list(filenames, cmp: string_compare)

    try:
        let prog = compile(filenames)
        log_info("OK")
        return 0
    except (error: CompilationError):
        log_error("HORROR")
        display_error(error)
        return 1

fn compile(filenames: List[String]) -> bc.Program except CompilationError:
    let module_map: Dictionary[ast.Module] = Dictionary()
    let std_module = get_std_module()
    module_map.insert(key: "std", value: std_module)

    let modules: List[ast.Module] = List()
    for filename in filenames:
        log_info("Parsing: {filename.value}")

        let program = parse_source(filename)
        log_trace("Parsed module: {program.name}")
        # ast.print_ast(program)
        modules.append(program)
        module_map.insert(key: program.name, value: program)
    
    topo_sort(modules)
    # TODO: topo-sort modules!

    for module in modules:
        bind_names(module, module_map)
        resolve_newops(module)
    
    for module3 in modules:
        ast.print_ast(module: module3)
        type_check(module: module3)
    
    for module4 in modules:
        transform(module: module4)
        ast.print_ast(module: module4)
        type_check(module: module4)

    for module5 in modules:
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
