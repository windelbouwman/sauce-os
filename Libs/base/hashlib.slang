
from std import str_len, str_get, ord

fn elf_hash(text: str) -> int:
    let h = 0
    let index = 0
    let n = str_len(text)
    while index < n:
        let c = str_get(text, index)
        h = (h << 4) + ord(c)
        let g = h & 0xF0000000
        if g != 0:
            h = h ^  (g >> 24)
        h = h & (0xFFFFFFFF ^ g)
        index += 1
        # assert h >= 0
    h

fn djb2(text: str) -> int:
    let hash = 5381
    let index = 0
    let n = str_len(text)
    while index < n:
        let c = str_get(text, index)
        # hash = 33 * hash + c
        hash = (hash << 5) + hash + ord(c)
        index += 1

    hash & 0xFFFFFFFF
