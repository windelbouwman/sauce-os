"""
Usage:

    $ python -m pytest test_compiler1.py -v

"""

import io
from pathlib import Path
from functools import lru_cache
import pytest

from compiler1.compiler import Compiler, CompilationOptions
from compiler1.errors import CompilationError

root_path = Path(__file__).resolve().parent
snippets_path = root_path / "examples" / "snippets"
example_filenames = sorted(snippets_path.glob("*.slang"))
ids = [filename.stem for filename in example_filenames]


@lru_cache()
def create_compiler2():
    options = CompilationOptions(run_code=False, backend="py")
    return Compiler(options)


def create_compiler(run_code=False, backend="py"):
    compiler = create_compiler2()
    compiler.options.run_code = run_code
    compiler.options.backend = backend
    return compiler


@pytest.mark.parametrize("filename", example_filenames, ids=ids)
@pytest.mark.parametrize("backend", ["vm", "py"])
def test_compiles(filename: Path, backend: str):
    compiler = create_compiler(run_code=True, backend=backend)
    f = io.StringIO()
    runtime_filename = root_path / "runtime" / "std.slang"
    compiler.do_compile([filename, runtime_filename], f)
    stdout = f.getvalue()

    # Compare with reference file (if one exists):
    reference_output_filename = filename.with_suffix(".stdout")
    if reference_output_filename.exists():
        expected_output = reference_output_filename.read_text()
        assert stdout == expected_output


def test_linkage():
    compiler = create_compiler(run_code=False)
    runtime_filename = root_path / "runtime" / "std.slang"
    linkage_path = root_path / "examples" / "linkage"
    sources = sorted(linkage_path.glob("*.slang"))
    sources.append(runtime_filename)
    f = io.StringIO()
    compiler.do_compile(sources, f)
    # print(f.getvalue())


def test_error_handling():
    """Test how a compilation error is handled"""
    compiler = create_compiler()
    f = io.StringIO()
    with pytest.raises(CompilationError):
        compiler.do_compile([("foo.slang", "x")], f)
