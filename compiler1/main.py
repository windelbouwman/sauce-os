"""Main entry point to the compiler."""

import sys
from rich.logging import RichHandler
from . import compiler, errors
import argparse
import logging
import glob


def main() -> int:
    # Split args after '--' into args for program
    if "--" in sys.argv:
        index = sys.argv.index("--")
        compiler_args = sys.argv[1:index]
        program_args = sys.argv[index + 1 :]
    else:
        compiler_args = sys.argv[1:]
        program_args = []

    parser = argparse.ArgumentParser()
    parser.add_argument("source", nargs="+", help="Source files")
    parser.add_argument("--output", "-o", help="File to write output to")
    parser.add_argument(
        "--verbose", "-v", action="count", default=0, help="Logging verbosity"
    )
    parser.add_argument("--dump-ast", "-d", action="store_true", help="")
    parser.add_argument(
        "--run-code", "-r", action="store_true", help="Run program after compilation"
    )
    parser.add_argument(
        "--backend",
        choices=["py", "vm"],
        default="vm",
        help="Which backend to use.",
    )
    args = parser.parse_args(args=compiler_args)
    if args.verbose > 1:
        loglevel = logging.DEBUG
    elif args.verbose > 0:
        loglevel = logging.INFO
    else:
        loglevel = logging.WARNING

    logging.basicConfig(
        level=loglevel, format="%(message)s", datefmt="[%X]", handlers=[RichHandler()]
    )
    logger = logging.getLogger("slangc")

    options = compiler.CompilationOptions(
        dump_ast=args.dump_ast,
        run_code=args.run_code,
        backend=args.backend,
        program_args=tuple(program_args),
    )

    sources = []
    for source in args.source:
        sources.extend(glob.glob(source))
    sources = list(sorted(set(sources)))

    if args.output:
        logger.info(f"Writing output to: {args.output}")
        f = open(args.output, "w")
    else:
        f = None

    try:
        compiler.do_compile(sources, f, options)
    except errors.CompilationError as ex:
        logger.error("Errors occurred during compilation!")
        errors.print_errors(ex.errors)
        return 1
    finally:
        if f:
            f.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
