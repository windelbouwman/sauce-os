"""
Usage:

    $ python -m pytest test_compiler1.py -v

"""

import glob
import os.path
import io
from compiler1 import compiler


def test_compiles(filename: str):
    options = compiler.CompilationOptions(dump_ast=False, run_code=True, backend="vm")
    f = io.StringIO()
    compiler.do_compile([filename], f, options)
    stdout = f.getvalue()

    # Compare with reference file (if one exists):
    reference_output_filename = os.path.splitext(filename)[0] + ".stdout"
    if os.path.exists(reference_output_filename):
        with open(reference_output_filename) as f:
            expected_output = f.read()
        assert stdout == expected_output


def pytest_generate_tests(metafunc):
    filenames = glob.glob("examples/*.slang")
    metafunc.parametrize("filename", filenames)
