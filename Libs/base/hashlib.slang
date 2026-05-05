module base.hashlib

from std import ord

pub fn elf_hash(text: str) -> uint32:
	var h = uint32(0)
	for c in text:
		h = (h << uint32(4)) + uint32(ord(c))
		let g = h & uint32(0xF0000000)
		if g != uint32(0):
			h = h ^ (g >> uint32(24))
		h = h & (uint32(0xFFFFFFFF) ^ g)
		# assert h >= 0
	h

pub fn djb2(text: str) -> uint32:
	var hash = uint32(5381)
	for c in text:
		# hash = 33 * hash + c
		hash = (hash << uint32(5)) + hash + uint32(ord(c))

	hash
