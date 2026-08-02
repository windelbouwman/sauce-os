module main
"""Test Path behavior"""

from std import print
from base.fs import Path, new_path
from base.unittest import assert_str_equals

pub fn main() -> int:
	let readme = new_path(filename: "readme.txt")
	let readme_md = readme.with_suffix(suffix: "md")
	assert_str_equals(readme_md.to_string(), "readme.md")
	assert_str_equals(readme_md.get_extension(), "md")

	print("OK")
	0
