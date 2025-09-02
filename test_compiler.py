"""
Build compiler, and test snippets.
"""

import subprocess
import sys
from pathlib import Path

import pytest

root_path = Path(__file__).resolve().parent
snippets_path = root_path / "examples" / "snippets"
example_filenames = sorted(snippets_path.glob("*.slang"))
ids = [filename.stem for filename in example_filenames]
std_module_path = root_path / "runtime" / "std.slang"


def run_compiler(args) -> str:
    # invoke compiler5 in build folder
    exe_path = root_path / "build" / "compiler5"
    result = subprocess.run([exe_path] + args, capture_output=True, check=True)
    return result.stdout.decode("ascii")


def check_reference_output(example_filename: Path, stdout: str):
    """Compare output with expected reference output"""
    reference_output_filename = example_filename.with_suffix(".stdout")
    if reference_output_filename.exists():
        expected_output = reference_output_filename.read_text()
        assert stdout == expected_output


@pytest.mark.parametrize("filename", example_filenames, ids=ids)
def test_examples_py_backend(filename: Path):
    """Test all examples can be compiled to python code

    Recipe:
    1. invoke python code generated from snippet
    2. compare example output with reference output

    """

    script_path = root_path / "build" / "python" / f"snippet-{filename.stem}.py"
    cmd = [sys.executable, script_path]
    result = subprocess.run(cmd, capture_output=True, check=True)
    stdout = result.stdout.decode("ascii")
    check_reference_output(filename, stdout)


@pytest.mark.parametrize("filename", example_filenames, ids=ids)
def test_examples_c_backend(filename: Path):
    """Test example can be compiled to C code

    Recipe:
    1. invoke slang compiler on the example, to produce C code
    """

    args = ["--backend-c", std_module_path, filename]
    run_compiler(args)


@pytest.mark.parametrize("filename", example_filenames, ids=ids)
def test_examples_slang_backend(filename: Path):
    """
    Recipe:
    1. invoke slang compiler on the example, to produce Slang code
    """

    args = ["--backend-slang", std_module_path, filename]
    run_compiler(args)


@pytest.mark.parametrize("filename", example_filenames, ids=ids)
def test_examples_bc_backend(filename: Path):
    """
    Test all examples can be compiled to bytecode.

    Recipe:
    1. invoke slang compiler on the example, to produce bytecode, and run this bytecode
    2. compare example output with reference output

    """

    args = ["--run", "--backend-bc", std_module_path, filename]
    stdout = run_compiler(args)
    check_reference_output(filename, stdout)


@pytest.mark.parametrize("filename", example_filenames, ids=ids)
def test_examples_exe(filename):
    """Test compiled executable against expected output."""
    exe_path = root_path / "build" / "c" / "snippets" / f"{filename.stem}.exe"
    result = subprocess.run([exe_path], capture_output=True, check=True)
    stdout = result.stdout.decode("ascii")
    check_reference_output(filename, stdout)
