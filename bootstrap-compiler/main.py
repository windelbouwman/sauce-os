
from rich.traceback import install
from rich.logging import RichHandler
import argparse
import logging
from .parsing import parse
from .ast import print_ast
from .analyze import analyze_ast
# from .codegeneration import gencode
from .cppgenerator import gencode
from .errors import CompilationError

logger = logging.getLogger('compiler')
# install(show_locals=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source')
    parser.add_argument('--output', default='output.txt')
    args = parser.parse_args()
    logformat = '%(asctime)s | %(levelname)8s | %(name)10.10s | %(message)s'
    # logging.basicConfig(level=logging.DEBUG, format=logformat)
    logging.basicConfig(
        level="NOTSET", format="%(message)s",
        datefmt="[%X]",
        handlers=[RichHandler()]
    )

    known_modules = {}
    do_compile(args.source, args.output, known_modules)


def do_compile(filename, output, known_modules):
    logger.info(f"Compiling {filename}")
    with open(filename, 'r') as f:
        code = f.read()
    try:
        ast = parse(code)
    except CompilationError:
        logger.error("Errors occurred during parsing!")

    else:
        print_ast(ast)
        if analyze_ast(ast, code):
            gencode(ast, output)
            logger.info('DONE&DONE')
        else:
            logger.error('Errors occurred during type checking!')


if __name__ == '__main__':
    main()
