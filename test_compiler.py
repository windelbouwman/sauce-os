"""
Build compiler, and test snippets.
"""

import os
import subprocess
import pytest
import glob
import sys
import io
from functools import lru_cache
from compiler1 import compiler, errors, builtins


example_filenames = list(glob.glob("examples/snippets/*.slang"))
sys.path.insert(0, "runtime")


@lru_cache
def slang_compiler():
    options = compiler.CompilationOptions(backend="py")
    sources = glob.glob("compiler/**/*.slang", recursive=True)
    sources.extend(glob.glob("Libs/base/*.slang"))
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
    compiled_here = False
    if compiled_here:

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
    else:
        # invoke compiler5 in build folder
        exe_path = os.path.join("build", "compiler5")
        result = subprocess.run([exe_path] + args, capture_output=True)
        stdout = result.stdout.decode("ascii")
        assert result.returncode == 0
        return stdout


def get_reference_output(example_filename):
    reference_output_filename = os.path.splitext(example_filename)[0] + ".stdout"
    if os.path.exists(reference_output_filename):
        with open(reference_output_filename) as f:
            expected_output = f.read()
            return expected_output


@pytest.mark.parametrize("filename", example_filenames)
def test_examples_py_backend(filename):
    """
    Test all examples can be compiled to python code

    Recipe:
    1. invoke slang compiler on the example, to produce python code (again)
    2. invoke example program
    3. compare example output with reference output

    """

    args = ["-rt", "--backend-py", "runtime/std.slang"] + [filename]
    program_py_code = run_compiler(args)

    # Execute produced python code:
    f2 = io.StringIO()
    program_global_map = builtins.get_builtins(args=[], stdout=f2)
    exec(program_py_code, program_global_map)

    def std_print(txt: str):
        print(txt, file=f2)

    program_global_map["std_print"] = std_print

    program_global_map["main2"]()
    stdout = f2.getvalue()

    reference_output = get_reference_output(filename)
    if reference_output:
        assert stdout == reference_output


@pytest.mark.parametrize("filename", example_filenames)
def test_examples_c_backend(filename):
    """
    Test example can be compiled to C code

    Recipe:
    1. invoke slang compiler on the example, to produce C code

    """

    args = ["--backend-c", "runtime/std.slang"] + [filename]
    run_compiler(args)

@pytest.mark.parametrize("filename", example_filenames)
def test_examples_slang_backend(filename):
    """
    Recipe:
    1. invoke slang compiler on the example, to produce Slang code

    """

    args = ["--backend-slang", "runtime/std.slang"] + [filename]
    run_compiler(args)

@pytest.mark.parametrize("filename", example_filenames)
def test_examples_bc_backend(filename):
    """
    Test all examples can be compiled to bytecode.

    Recipe:
    1. invoke slang compiler on the example, to produce bytecode, and run this bytecode
    2. compare example output with reference output

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
    exe_path = os.path.join("build", "c", "snippets", exe_filename)

    result = subprocess.run([exe_path], capture_output=True)
    stdout = result.stdout.decode("ascii")
    assert result.returncode == 0

    reference_output = get_reference_output(filename)
    if reference_output:
        assert stdout == reference_output
