
from strlib import split_string

fn basename(path: str) -> str:
    # retrieve 'bla' from 'for/bar/bla.txt'
    let base = split_string(text: path, sep: '/').last()
    return split_string(text: base, sep: '.').first()
