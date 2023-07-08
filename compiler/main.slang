
from std import print
import ast
import bc
from errors import display_error, CompilationError
from parsing import parse_source
from namebinding import bind_names
from pass3 import resolve_newops
from typechecking import type_check
from utils import log_info, log_error
from ir_gen import gen_bytecode
from pygenerator import gen_python
from transforms import transform
from builtins import get_std_module
from datatypes import List, String, new_string, Dictionary, Result


fn main() -> int:
    # let filename = "dummy.slang"
    let filenames: List[String] = List()

    # Manually sorted list of compiler sources:
    filenames.append(new_string("compiler/location.slang"))
    filenames.append(new_string("compiler/utils.slang"))
    filenames.append(new_string("compiler/token.slang"))
    filenames.append(new_string("compiler/datatypes.slang"))
    filenames.append(new_string("compiler/bc.slang"))
    filenames.append(new_string("compiler/errors.slang"))
    filenames.append(new_string("compiler/lexer.slang"))
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

    # filenames.append(new_string("examples/hello-world.slang"))
    # filenames.append(new_string("examples/callings.slang"))
    # filenames.append(new_string("examples/expressions.slang"))
    # filenames.append(new_string("examples/mandel.slang"))
    # filenames.append(new_string("examples/structs-passing.slang"))
    # filenames.append(new_string("examples/loops.slang"))
    try:
        let prog = compile(filenames)
        log_info("OK")
        return 0
    except (err: CompilationError):
        log_error("HORROR")
        display_error(err)
        return 1

fn compile(filenames: List[String]) -> bc.Program except CompilationError:
    # TODO: sort filenames!

    let module_map: Dictionary[ast.Module] = Dictionary()
    let std_module = get_std_module()
    module_map.insert("std", std_module)

    let modules: List[ast.Module] = List()
    for filename in filenames:
        log_info("Compiling: {filename.value}")

        let program = parse_source(filename)
        log_info("Parsed module: {program.name}")
        # ast.print_ast(program)
        modules.append(program)
        module_map.insert(program.name, program)
    
    # TODO: topo-sort modules!

    for module in modules:
        bind_names(module, module_map)
        resolve_newops(module)
    
    for module3 in modules:
        # ast.print_ast(module3)
        type_check(module3)
    
    for module4 in modules:
        transform(module4)

    # TODO!
    for module2 in modules:
        # let prog = gen_bytecode(module2)
        #log_info("generating bytecode: {module2.name}")
        # gen_python(module2)
        pass

    let prog = bc.new_program()
    return prog
