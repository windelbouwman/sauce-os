"""
Usage:

    $ python -m pytest test_compiler1.py -v

"""

import glob
import os.path
import io
import pytest
from compiler1 import compiler

# Skip slow mandelbrot test for now:
exclusions = ["mandel"]


def include_example(filename):
    for exclusion in exclusions:
        if exclusion in filename:
            return False
    return True


example_filenames = list(filter(include_example, glob.glob("examples/*.slang")))


@pytest.mark.parametrize("filename", example_filenames)
@pytest.mark.parametrize("backend", ["vm", "py"])
def test_compiles(filename: str, backend: str):
    options = compiler.CompilationOptions(
        dump_ast=False, run_code=True, backend=backend
    )
    f = io.StringIO()
    runtime_filename = "runtime/std.slang"
    compiler.do_compile([filename, runtime_filename], f, options)
    stdout = f.getvalue()

    # Compare with reference file (if one exists):
    reference_output_filename = os.path.splitext(filename)[0] + ".stdout"
    if os.path.exists(reference_output_filename):
        with open(reference_output_filename) as f:
            expected_output = f.read()
        assert stdout == expected_output
