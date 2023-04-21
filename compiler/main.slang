
from std import print
import ast
from parsing import parse_source
from namebinding import bind_names
from pass3 import resolve_newops
from ir_gen import gen_bytecode
from builtins import get_std_module
from datatypes import List, String, new_string, Dictionary


fn main() -> int:
    # let filename = "dummy.slang"
    let filenames: List[String] = List()
    # filenames.append(new_string("compiler/main.slang"))
    # filenames.append(new_string("compiler/lexer.slang"))
    # filenames.append(new_string("compiler/parsing.slang"))
    # filenames.append(new_string("compiler/datatypes.slang"))
    # filenames.append(new_string("compiler/ast.slang"))
    filenames.append(new_string("compiler/utils.slang"))
    filenames.append(new_string("compiler/location.slang"))
    filenames.append(new_string("compiler/errors.slang"))
    # filenames.append(new_string("compiler/namebinding.slang"))
    # filenames.append(new_string("examples/hello-world.slang"))
    # filenames.append(new_string("examples/callings.slang"))
    # filenames.append(new_string("examples/expressions.slang"))
    # filenames.append(new_string("examples/mandel.slang"))
    # filenames.append(new_string("examples/structs-passing.slang"))
    # filenames.append(new_string("examples/loops.slang"))
    # compile(filenames)
    


# fn compile(filenames: List[String]):
    # TODO: sort filenames!

    let module_map: Dictionary[ast.Module] = Dictionary()
    let std_module = get_std_module()
    module_map.insert("std", std_module)

    let modules: List[ast.Module] = List()
    for filename in filenames:
        print("Compiling: {filename.value}")

        case parse_source(filename):
            Ok(program):
                print("Parsed module: {program.name}")
                # ast.print_ast(program)
                modules.append(program)
                module_map.insert(program.name, program)
            Error(error):
                print("Compilation failed: {error.location.row}:{error.location.column} -> {error.message}")
                # return 1
    
    # TODO: topo-sort modules!

    for module in modules:
        bind_names(module, module_map)
        resolve_newops(module)

    print("generating bytecode")
    # return 1
    # TODO:
    for module2 in modules:
        gen_bytecode(module2)
    
    print("DONE & DONE")
    return 0
