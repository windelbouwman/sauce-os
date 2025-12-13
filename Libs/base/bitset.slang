""" Bit set data type.
"""

from vectype import Vector, new_vector

pub class BitSet:
	""" Compactly store an vector of booleans
	"""
	var m_integers: Vector[int] = new_vector()
	var m_count: int = 0

	pub fn count() -> int:
		m_count

	pub fn set(bit?: int):
		if not isset(bit):
			m_count += 1
			let index = bit_slot(bit)
			while not (index < m_integers.len()):
				m_integers.append(0)
			let bits = m_integers.get(index)
			let mask = bit_mask(bit)
			m_integers.set(index, value: bits | mask)

	pub fn clear(bit?: int):
		if isset(bit):
			m_count -= 1
			let index = bit_slot(bit)
			let bits = m_integers.get(index)
			let mask = bit_mask(bit)
			m_integers.set(index, value: bits ^ mask)

	pub fn isset(bit?: int) -> bool:
		let index = bit_slot(bit)
		if index < m_integers.len():
			let bits = m_integers.get(index)
			let mask = bit_mask(bit)
			bits & mask == mask
		else:
			false

	pub fn union(other: BitSet) -> BitSet:
		BitSet()

let n_bits_per_int: int = 57

fn bit_mask(bit: int) -> int:
	1 << (bit % n_bits_per_int)

fn bit_slot(bit: int) -> int:
	bit / n_bits_per_int
