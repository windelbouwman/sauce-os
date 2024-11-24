
from std import ord

fn elf_hash(text: str) -> int:
    let h = 0
    for c in text:
        h = (h << 4) + ord(c)
        let g = h & 0xF0000000
        if g != 0:
            h = h ^  (g >> 24)
        h = h & (0xFFFFFFFF ^ g)
        # assert h >= 0
    h

fn djb2(text: str) -> int:
    let hash = 5381
    for c in text:
        # hash = 33 * hash + c
        hash = (hash << 5) + hash + ord(c)

    hash & 0xFFFFFFFF
