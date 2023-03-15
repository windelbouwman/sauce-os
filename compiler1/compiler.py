
""" Compiler driver.
"""

from dataclasses import dataclass
import logging

from . import ast, types
from .parsing import parse_file
from .analyze import analyze_ast
from .transforms import transform
from .cppgenerator import gencode

logger = logging.getLogger('compiler')


@dataclass
class CompilationOptions:
    dump_ast: bool = False


def std_module():
    return ast.BuiltinModule(
        'std', {
            'print': ast.BuiltinFunction('std_print', [types.str_type], types.void_type),
            'int_to_str': ast.BuiltinFunction('std_int_to_str', [types.int_type], types.str_type),
            'float_to_str': ast.BuiltinFunction('std_float_to_str', [types.float_type], types.str_type),
        })


def do_compile(filenames: list[str], output, known_modules, options: CompilationOptions):
    """ Compile a list of module.
    """
    modules = []
    for filename in filenames:
        module = parse_file(filename)
        modules.append(module)
        if options.dump_ast:
            logger.info('Dumping AST')
            ast.print_ast(module)

    for module in modules:
        analyze_ast(module, known_modules, options)
        transform(module)

        if options.dump_ast:
            logger.info('Dumping AST')
            ast.print_ast(module)

        if output:
            with open(output, 'w') as f:
                gencode(module, f=f)
        else:
            gencode(module)
        logger.info('DONE&DONE')
