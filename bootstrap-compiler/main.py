

from dataclasses import dataclass
from rich.traceback import install
from rich.logging import RichHandler
import argparse
import logging
from .parsing import parse
from .ast import print_ast
from . import ast, types
from .analyze import analyze_ast
# from .codegeneration import gencode
from .cppgenerator import gencode
from .errors import CompilationError
from .transforms import LoopRewriter

logger = logging.getLogger('compiler')
# install(show_locals=True)


@dataclass
class Options:
    dump_ast: bool = False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source')
    parser.add_argument('--output')
    parser.add_argument('--dump-ast', action='store_true')
    args = parser.parse_args()
    print(args)
    logformat = '%(asctime)s | %(levelname)8s | %(name)10.10s | %(message)s'
    # logging.basicConfig(level=logging.DEBUG, format=logformat)
    logging.basicConfig(
        level="NOTSET", format="%(message)s",
        datefmt="[%X]",
        handlers=[RichHandler()]
    )

    options = Options(dump_ast=args.dump_ast)

    known_modules = {'std': std_module()}
    do_compile(args.source, args.output, known_modules, options)


def std_module():
    return ast.BuiltinModule(
        'std', {
            'print': ast.BuiltinFunction('std_print', [types.str_type], types.void_type),
            'int_to_str': ast.BuiltinFunction('std_int_to_str', [types.int_type], types.str_type),
            'float_to_str': ast.BuiltinFunction('std_float_to_str', [types.float_type], types.str_type),
        })


def do_compile(filename, output, known_modules, options: Options):
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
            LoopRewriter().transform(ast)

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


if __name__ == '__main__':
    main()
