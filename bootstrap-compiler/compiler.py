
""" Compiler driver.
"""

from dataclasses import dataclass
import logging

from .parsing import parse
from .ast import print_ast
from . import ast, types
from .analyze import analyze_ast
# from .codegeneration import gencode
from .cppgenerator import gencode
from .errors import CompilationError
from .transforms import transform

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


def do_compile(filename: str, output, known_modules, options: CompilationOptions):
    logger.info(f"Compiling {filename}")
    with open(filename, 'r') as f:
        code = f.read()
    try:
        ast = parse(code)
    except CompilationError:
        logger.error("Errors occurred during parsing!")

    else:
        if options.dump_ast:
            logger.info('Dumping AST')
            print_ast(ast)

        if analyze_ast(ast, code, known_modules, options):
            transform(ast)

            if options.dump_ast:
                logger.info('Dumping AST')
                print_ast(ast)

            if output:
                with open(output, 'w') as f:
                    gencode(ast, f=f)
            else:
                gencode(ast)
            logger.info('DONE&DONE')
        else:
            logger.error('Errors occurred during type checking!')
