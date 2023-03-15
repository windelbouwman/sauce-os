

from rich.traceback import install
from rich.logging import RichHandler
from . import compiler
import argparse
import logging


# install(show_locals=True)


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

    options = compiler.CompilationOptions(dump_ast=args.dump_ast)

    known_modules = {'std': compiler.std_module()}
    compiler.do_compile(args.source, args.output, known_modules, options)


if __name__ == '__main__':
    main()
