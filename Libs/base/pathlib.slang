module base.pathlib

from strlib import split_string
from std import get_path_separator
from listtype import List

pub fn basename(path: str) -> str:
	"""retrieve 'bla' from 'for/bar/bla.txt'"""
	let base = split_path(path).last()
	split_string(text: base, sep: '.').first()

pub fn split_path(path: str) -> List[str]:
	let path_sep = get_path_separator()
	split_string(text: path, sep: path_sep)
