""" Helper script to bootstrap the compiler

Use the python based bootstrap compiler to compile the compiler itself.

"""

import sys
import glob
import logging
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--verbose", "-v", action="count", default=0, help="Verbosity")
args = parser.parse_args()
if args.verbose > 1:
    loglevel = logging.DEBUG
elif args.verbose > 0:
    loglevel = logging.INFO
else:
    loglevel = logging.WARNING

# import cProfile
# import pstats
from compiler1 import compiler, errors, builtins

logging.basicConfig(level=loglevel)
options = compiler.CompilationOptions(backend="py")
sources = glob.glob("compiler/**/*.slang", recursive=True)
sources.extend(glob.glob("Libs/base/*.slang"))
sources.append("runtime/std.slang")

output_filename = "build/tmp-compiler.py"
try:
    # profiler = cProfile.Profile()
    # profiler.enable()
    with open(output_filename, "w") as f:
        print(builtins.BUILTINS_PY_IMPL, file=f)
        compiler.do_compile(sources, f, options)
        print("sys.exit(main())", file=f)
    # profiler.disable()
    # stats = pstats.Stats(profiler)
    # stats.print_stats()
    # stats.print_stats("if")
except errors.CompilationError as ex:
    print("ERRORS")
    errors.print_errors(ex.errors)
    sys.exit(1)
else:
    print(f"OK --> {output_filename}")
