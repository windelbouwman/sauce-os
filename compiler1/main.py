

from rich.traceback import install
from rich.logging import RichHandler
from rich.progress import Progress
from . import compiler, errors
import argparse
import logging


# install(show_locals=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', nargs='+', help='Source files')
    parser.add_argument('--output', help='File to write output to')
    parser.add_argument('--dump-ast', action='store_true')
    args = parser.parse_args()
    logging.basicConfig(
        level="NOTSET", format="%(message)s",
        datefmt="[%X]",
        handlers=[RichHandler()]
    )
    logger = logging.getLogger('main')

    options = compiler.CompilationOptions(dump_ast=args.dump_ast)

    try:
        with Progress() as progress:
            task = progress.add_task(':hammer:Compiling')
            compiler.do_compile(args.source, args.output,
                                options, progress, task)
    except errors.CompilationError as ex:
        logger.error("Errors occurred during compilation!")
        errors.print_errors(ex.errors)


if __name__ == '__main__':
    main()
