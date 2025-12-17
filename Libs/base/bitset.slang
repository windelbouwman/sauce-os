""" Bit set data type.
"""

from utils import unimplemented, panic
from vectype import Vector, new_vector

pub fn new_bitset(n: int) -> BitSet:
	""" Create a bit set with n bits. """
	let n_integers = (n + n_bits_per_int - 1) / n_bits_per_int
	var data = [n_integers : int]
	var i = 0
	while i < n_integers:
		data[i] = 0
		i += 1
	BitSet(m_integers: data, m_num_integers: n_integers, m_width: n)

pub class BitSet:
	""" Compactly store an vector of booleans
	"""
	pub var m_integers: [int]
	pub var m_num_integers: int
	pub var m_width: int

	pub fn set(bit?: int):
		if bit < m_width:
			let index = bit_slot(bit)
			let mask = bit_mask(bit)
			m_integers[index] = m_integers[index] | mask
		else:
			panic("set: bit out of range")

	pub fn clear(bit?: int):
		if bit < m_width:
			let index = bit_slot(bit)
			let mask = bit_mask(bit)
			let bits = m_integers[index]
			if bits & mask == mask:
				m_integers[index] = bits ^ mask
		else:
			panic("clear: bit out of range")

	pub fn isset(bit?: int) -> bool:
		if bit < m_width:
			let index = bit_slot(bit)
			let mask = bit_mask(bit)
			let bits = m_integers[index]
			bits & mask == mask
		else:
			panic("isset: bit out of range")

	pub fn or_assign(other: BitSet):
		if m_width == other.m_width:
			var index = 0
			while index < m_num_integers:
				m_integers[index] = m_integers[index] | other.m_integers[index]
				index += 1
		else:
			panic("or_assign: width mismatch")

	pub fn and_assign(other: BitSet):
		if m_width == other.m_width:
			var index = 0
			while index < m_num_integers:
				m_integers[index] = m_integers[index] & other.m_integers[index]
				index += 1
		else:
			panic("and_assign: width mismatch")

	pub fn andnot_assign(other: BitSet):
		if m_width == other.m_width:
			let full_mask = (1 << n_bits_per_int) - 1
			var index = 0
			while index < m_num_integers:
				m_integers[index] = m_integers[index] & (full_mask ^ other.m_integers[index])
				index += 1
		else:
			panic("andnot_assign: width mismatch")

let n_bits_per_int: int = 57

fn bit_mask(bit: int) -> int:
	1 << (bit % n_bits_per_int)

fn bit_slot(bit: int) -> int:
	bit / n_bits_per_int
