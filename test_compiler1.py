
"""
Usage:

    $ python -m pytest test_compiler1.py -v

"""

import glob
from compiler1 import compiler


def test_compiles(filename):
    options = compiler.CompilationOptions(dump_ast=True)
    known_modules = {'std': compiler.std_module()}
    compiler.do_compile(filename, None, known_modules, options)


def pytest_generate_tests(metafunc):
    filenames = glob.glob('examples/*.slang')
    metafunc.parametrize('filename', filenames)
