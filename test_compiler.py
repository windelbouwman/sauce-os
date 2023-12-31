"""
Build compiler, and test snippets.
"""

import os
import subprocess
import pytest
import glob
import io
from functools import lru_cache
from compiler1 import compiler, errors, builtins


exclusions = ["mandel"]


def include_example(filename):
    for exclusion in exclusions:
        if exclusion in filename:
            return False
    return True


example_filenames = list(filter(include_example, glob.glob("examples/*.slang")))


@lru_cache
def slang_compiler():
    options = compiler.CompilationOptions(backend="py")
    sources = glob.glob("compiler/**/*.slang", recursive=True)
    sources.append("runtime/std.slang")

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


def run_compiler(args):
    slang_compiler_py_code = slang_compiler()

    f1 = io.StringIO()
    global_map = builtins.get_builtins(args=args, stdout=f1)
    exec(slang_compiler_py_code, global_map)
    exit_code = global_map["main"]()
    compiler_output = f1.getvalue()
    if exit_code == 0:
        return compiler_output
    else:
        print(compiler_output)
        raise ValueError(f"Compiler failed: {exit_code}")


def get_reference_output(example_filename):
    reference_output_filename = os.path.splitext(example_filename)[0] + ".stdout"
    if os.path.exists(reference_output_filename):
        with open(reference_output_filename) as f:
            expected_output = f.read()
            return expected_output


@pytest.mark.parametrize("filename", example_filenames)
def test_examples_py_backend(filename):
    """
    Test all examples can be compiled using our slang compiler

    Recipe:
    1. compile slang compiler to python
    2. invoke slang compiler on the example, to produce python code (again)
    3. invoke example program
    4. compare example output with reference output

    """

    # Compile example using bootstrapped compiler:
    args = ["-rt", "--backend-py", "runtime/std.slang"] + [filename]
    program_py_code = run_compiler(args)

    # Execute produced python code:
    f2 = io.StringIO()
    program_global_map = builtins.get_builtins(args=[], stdout=f2)
    exec(program_py_code, program_global_map)
    program_global_map["main2"]()
    stdout = f2.getvalue()

    reference_output = get_reference_output(filename)
    if reference_output:
        assert stdout == reference_output


@pytest.mark.parametrize("filename", example_filenames)
def test_examples_c_backend(filename):
    """
    Test all examples can be compiled using our slang compiler

    Recipe:
    1. compile slang compiler to python
    2. invoke slang compiler on the example, to produce C code

    """

    # Compile example using bootstrapped compiler:
    args = ["--backend-c", "runtime/std.slang"] + [filename]
    run_compiler(args)


@pytest.mark.parametrize("filename", example_filenames)
def test_examples_bc_backend(filename):
    """
    Test all examples can be compiled to bytecode.

    Recipe:
    1. compile slang compiler to python
    2. invoke slang compiler on the example, to produce bytecode, and run this bytecode
    3. compare example output with reference output

    """

    args = ["--run", "--backend-bc", "runtime/std.slang"] + [filename]
    stdout = run_compiler(args)

    reference_output = get_reference_output(filename)
    if reference_output:
        assert stdout == reference_output


@pytest.mark.parametrize("filename", example_filenames)
def test_examples_exe(filename):
    """
    Test compiled executable against expected output.

    """

    exe_filename = os.path.splitext(os.path.basename(filename))[0] + ".exe"
    exe_path = os.path.join("build", "c", exe_filename)

    result = subprocess.run([exe_path], capture_output=True)
    stdout = result.stdout.decode("ascii")
    assert result.returncode == 0

    reference_output = get_reference_output(filename)
    if reference_output:
        assert stdout == reference_output
