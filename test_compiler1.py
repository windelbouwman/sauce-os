"""
Usage:

    $ python -m pytest test_compiler1.py -v

"""

import io
from pathlib import Path

import pytest

from compiler1 import compiler

root_path = Path(__file__).resolve().parent
snippets_path = root_path / "examples" / "snippets"
example_filenames = sorted(snippets_path.glob("*.slang"))
ids = [filename.stem for filename in example_filenames]


@pytest.mark.parametrize("filename", example_filenames, ids=ids)
@pytest.mark.parametrize("backend", ["vm", "py"])
def test_compiles(filename: Path, backend: str):
    options = compiler.CompilationOptions(
        dump_ast=False, run_code=True, backend=backend
    )
    f = io.StringIO()
    runtime_filename = root_path / "runtime" / "std.slang"
    compiler.do_compile([filename, runtime_filename], f, options)
    stdout = f.getvalue()

    # Compare with reference file (if one exists):
    reference_output_filename = filename.with_suffix(".stdout")
    if reference_output_filename.exists():
        expected_output = reference_output_filename.read_text()
        assert stdout == expected_output
