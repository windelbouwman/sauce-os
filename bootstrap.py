""" Helper script to bootstrap the compiler

Use the python based bootstrap compiler to compile the compiler itself.

"""

import sys
import glob
import logging
from compiler1 import compiler, errors, builtins

logging.basicConfig(level=logging.WARNING)
options = compiler.CompilationOptions(backend="py")
sources = glob.glob("compiler/**/*.slang", recursive=True)

output_filename = "build/tmp-compiler.py"
try:
    with open(output_filename, "w") as f:
        print(builtins.BUILTINS_PY_IMPL, file=f)
        compiler.do_compile(sources, f, options)
        print("sys.exit(main())", file=f)
except errors.CompilationError as ex:
    print("ERRORS")
    errors.print_errors(ex.errors)
    sys.exit(1)
else:
    print(f"OK --> {output_filename}")
