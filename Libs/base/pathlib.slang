
from strlib import split_string
from std import get_path_separator

fn basename(path: str) -> str:
    # retrieve 'bla' from 'for/bar/bla.txt'
    let path_sep = get_path_separator()
    let base = split_string(text: path, sep: path_sep).last()
    return split_string(text: base, sep: '.').first()
