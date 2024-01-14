"""
Usage:

    $ python -m pytest test_compiler1.py -v

"""

import glob
import os.path
import io
import pytest
from compiler1 import compiler


example_filenames = list(glob.glob("examples/snippets/*.slang"))


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
