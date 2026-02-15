"""
Build compiler, and test snippets.
"""

import subprocess
import sys
import re
from pathlib import Path

import pytest

root_path = Path(__file__).resolve().parent
snippets_path = root_path / "examples" / "snippets"
example_filenames = sorted(snippets_path.glob("*.slang"))
ids = [filename.stem for filename in example_filenames]
std_module_path = root_path / "runtime" / "std.slang"


def is_aoc_folder(p: Path) -> bool:
    return p.is_dir() and re.match("^[12][0-9]{5}$", p.stem)


aoc_path = root_path / "examples" / "aoc"
aoc_folders = sorted(filter(is_aoc_folder, aoc_path.glob("*")))
aoc_ids = [f.stem for f in aoc_folders]


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
@pytest.mark.parametrize("backend", ["x86", "c", "c2", "py", "bc"])
def test_snippet(filename: Path, backend: str):
    """Test compiled snippet executable against expected snippet output."""
    if backend in ("x86", "c", "c2"):
        exe_path = root_path / "build" / backend / "snippets" / f"{filename.stem}.exe"
        cmd = [exe_path]
    elif backend == "py":
        script_path = root_path / "build" / "python" / f"snippet-{filename.stem}.py"
        cmd = [sys.executable, script_path]
    elif backend == "bc":
        exe_path = root_path / "build" / "compiler5"
        cmd = [exe_path, "--run", "--backend-bc", std_module_path, filename]
    else:
        raise NotImplementedError(f"Backend: {backend}")

    result = subprocess.run(cmd, capture_output=True, check=True)
    stdout = result.stdout.decode("ascii")
    check_reference_output(filename, stdout)


@pytest.mark.parametrize("folder", aoc_folders, ids=aoc_ids)
@pytest.mark.parametrize("backend", ["x86", "py"])
def test_aoc(folder: Path, backend: str):
    """Test the given advent of code puzzle solution."""
    example_path = folder / "example.txt"
    output_path = folder / "output.txt"

    if backend == "py":
        script_path = root_path / "build" / "python" / f"aoc-{folder.stem}.py"
        if script_path.exists():
            cmd = [sys.executable, script_path]
        else:
            pytest.skip("AoC solution not compiled to python")
    elif backend == "x86":
        exe_path = root_path / "build" / "x86" / f"aoc_{folder.stem}.exe"
        if exe_path.exists():
            cmd = [exe_path]
        else:
            pytest.skip("AoC solution not compiled to x86")
    else:
        raise NotImplementedError(f"Backend: {backend}")
    cmd.append(example_path)
    result = subprocess.run(cmd, capture_output=True, check=True)
    stdout = result.stdout.decode("ascii")
    expected_output = output_path.read_text()
    assert stdout == expected_output
