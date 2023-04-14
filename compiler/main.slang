
from std import print
import ast
from parsing import parse_source
from namebinding import bind_names
from ir_gen import gen_bytecode
from datatypes import List, String, new_string


fn main() -> int:
    # let filename = "dummy.slang"
    let filenames: List[String] = List()
    #filenames.append(new_string("compiler/main.slang"))
    #filenames.append(new_string("compiler/lexer.slang"))
    #filenames.append(new_string("compiler/parsing.slang"))
    #filenames.append(new_string("compiler/ast.slang"))
    # filenames.append(new_string("examples/hello-world.slang"))
    filenames.append(new_string("examples/callings.slang"))
    # filenames.append(new_string("examples/expressions.slang"))
    # filenames.append(new_string("examples/mandel.slang"))
    # filenames.append(new_string("examples/loops.slang"))
    # compile(filenames)
    


# fn compile(filenames: List[String]):
    # TODO: sort filenames!
    let modules: List[ast.Module] = List()
    for filename in filenames:
        print("Compiling: {filename.value}")
        case parse_source(filename.value):
            Ok(program):
                print("Parsed module: {program.name}")
                ast.print_ast(program)
                modules.append(program)
            Error(error):
                print("Compilation failed: {error.location.row}:{error.location.column} -> {error.message}")
                return 1
    
    # TODO: topo-sort modules!

    for module in modules:
        bind_names(module)

    print("generating bytecode")
    # return 1
    # TODO:
    for module2 in modules:
        gen_bytecode(module2)
    
    print("DONE & DONE")
    return 0
