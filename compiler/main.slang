
from std import print
import ast
from parsing import parse_source
from datatypes import List, String, new_string


fn main() -> int:
    # let filename = "dummy.slang"
    let filenames: List[String] = List()
    # filenames.append(new_string("compiler/main.slang"))
    # filenames.append(new_string("compiler/lexer.slang"))
    # filenames.append(new_string("compiler/parsing.slang"))
    # filenames.append(new_string("compiler/ast.slang"))
    filenames.append(new_string("examples/hello-world.slang"))
    compile(filenames)
    return 0


fn compile(filenames: List[String]):
    # TODO: topo-sort filenames!
    for filename in filenames:
        print("Compiling: {filename.value}")
        case parse_source(filename.value):
            Ok(program):
                print("Parsed module: {program.name}")
                ast.print_ast(program)
            Error(error):
                print("Compilation failed: {error.message}")
