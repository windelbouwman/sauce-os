"""
Usage:

    $ python -m pytest test_compiler1.py -v

"""

import glob
import os.path
import io
import pytest
from compiler1 import compiler


@pytest.mark.parametrize("filename", glob.glob("examples/*.slang"))
@pytest.mark.parametrize("backend", ["vm", "py"])
def test_compiles(filename: str, backend: str):
    # backend "cpp"

    # Skip slow mandelbrot test for now:
    if "mandel" in filename:
        return

    options = compiler.CompilationOptions(
        dump_ast=False, run_code=True, backend=backend
    )
    f = io.StringIO()
    compiler.do_compile([filename], f, options)
    stdout = f.getvalue()

    # Compare with reference file (if one exists):
    reference_output_filename = os.path.splitext(filename)[0] + ".stdout"
    if os.path.exists(reference_output_filename):
        with open(reference_output_filename) as f:
            expected_output = f.read()
        assert stdout == expected_output
