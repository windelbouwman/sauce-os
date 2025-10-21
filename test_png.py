"""
Run PNG images test-suite
"""

import subprocess
from pathlib import Path

import pytest

root_path = Path(__file__).resolve().parent
snippets_path = root_path / "pruttle" / "png-test-suite"
example_filenames = sorted(snippets_path.glob("*.png"))
ids = [filename.stem for filename in example_filenames]


@pytest.mark.parametrize("filename", example_filenames, ids=ids)
def test_png(filename: Path):
    # print(filename)
    app_exe = "./build/c/apps/write_image.exe"
    res = subprocess.run([app_exe, "-v", "-v", filename], check=True)
    print(res)
