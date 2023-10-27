"""
Build compiler, and test snippets.
"""

import os
import pytest
import glob
import io
from functools import lru_cache
from compiler1 import compiler, errors, builtins


@lru_cache
def slang_compiler():
    options = compiler.CompilationOptions(backend="py")
    sources = glob.glob("compiler/*.slang")

    f = io.StringIO()
    try:
        compiler.do_compile(sources, f, options)
    except errors.CompilationError as ex:
        print("ERRORS")
        errors.print_errors(ex.errors)
        raise ValueError("No compiler")
    else:
        print("OK")
        py_code = f.getvalue()
        # with open("tmptmptmp.py", "w") as f2:
        #    f2.write(py_code)
        return py_code


@pytest.mark.parametrize("filename", glob.glob("examples/*.slang"))
def test_examples_py_backend(filename):
    """
    Test all examples can be compiled using our slang compiler

    Recipe:
    1. compile slang compiler to python
    2. invoke slang compiler on the example, to produce python code (again)
    3. invoke example program
    4. compare example output with reference output

    """
    slang_compiler_py_code = slang_compiler()

    # Compile example using bootstrapped compiler:
    f1 = io.StringIO()
    global_map = builtins.get_builtins(args=["-rt"] + [filename], stdout=f1)
    exec(slang_compiler_py_code, global_map)
    exit_code = global_map["main"]()
    program_py_code = f1.getvalue()
    if exit_code != 0:
        print(program_py_code)
        raise ValueError(f"Compiler failed: {exit_code}")

    # Execute produced python code:
    f2 = io.StringIO()
    program_global_map = builtins.get_builtins(args=[], stdout=f2)
    exec(program_py_code, program_global_map)
    program_global_map["main2"]()
    stdout = f2.getvalue()

    reference_output_filename = os.path.splitext(filename)[0] + ".stdout"
    if os.path.exists(reference_output_filename):
        with open(reference_output_filename) as f:
            expected_output = f.read()
        assert stdout == expected_output


@pytest.mark.parametrize("filename", glob.glob("examples/*.slang"))
def test_examples_c_backend(filename):
    """
    Test all examples can be compiled using our slang compiler

    Recipe:
    1. compile slang compiler to python
    2. invoke slang compiler on the example, to produce C code

    """
    slang_compiler_py_code = slang_compiler()

    # Compile example using bootstrapped compiler:
    f1 = io.StringIO()
    global_map = builtins.get_builtins(args=["-cv2"] + [filename], stdout=f1)
    exec(slang_compiler_py_code, global_map)
    exit_code = global_map["main"]()
    program_c_code = f1.getvalue()
    print(program_c_code)
    if exit_code != 0:
        print(program_c_code)
        raise ValueError(f"Compiler failed: {exit_code}")
