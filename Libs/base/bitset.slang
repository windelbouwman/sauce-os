""" Bit set data type.
"""

from utils import unimplemented, panic
from vectype import Vector, new_vector
from optiontype import Option
from rt import ctz, popcnt

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

	pub fn add(bit?: int):
		set(bit)

	pub fn clear(bit?: int):
		if bit < m_width:
			let index = bit_slot(bit)
			let mask = bit_mask(bit)
			let bits = m_integers[index]
			if bits & mask == mask:
				m_integers[index] = bits ^ mask
		else:
			panic("clear: bit out of range")

	pub fn remove(bit?: int):
		clear(bit)

	pub fn isset(bit?: int) -> bool:
		if bit < m_width:
			let index = bit_slot(bit)
			let mask = bit_mask(bit)
			let bits = m_integers[index]
			bits & mask == mask
		else:
			panic("isset: bit out of range")

	pub fn contains(bit?: int) -> bool:
		isset(bit)

	pub fn or_assign(other?: BitSet):
		if m_width == other.m_width:
			var index = 0
			while index < m_num_integers:
				m_integers[index] = m_integers[index] | other.m_integers[index]
				index += 1
		else:
			panic("or_assign: width mismatch")

	pub fn and_assign(other?: BitSet):
		if m_width == other.m_width:
			var index = 0
			while index < m_num_integers:
				m_integers[index] = m_integers[index] & other.m_integers[index]
				index += 1
		else:
			panic("and_assign: width mismatch")

	pub fn andnot_assign(other?: BitSet):
		if m_width == other.m_width:
			let full_mask = (1 << n_bits_per_int) - 1
			var index = 0
			while index < m_num_integers:
				m_integers[index] = m_integers[index] & (full_mask ^ other.m_integers[index])
				index += 1
		else:
			panic("andnot_assign: width mismatch")

	pub fn clone() -> BitSet:
		let b = new_bitset(n: m_width)
		b.or_assign(this)
		b

	pub fn equals(other?: BitSet) -> bool:
		if m_width == other.m_width:
			var index = 0
			while index < m_num_integers:
				if m_integers[index] == other.m_integers[index]:
					index += 1
				else:
					return false
			true
		else:
			false

	pub fn len() -> int:
		var index = 0
		var s = 0
		while index < m_num_integers:
			s += popcnt(m_integers[index])
			index += 1
		s

	pub fn is_empty() -> bool:
		var index = 0
		while index < m_num_integers:
			if m_integers[index] != 0:
				return false
			index += 1
		true

	pub fn first() -> int:
		var index = 0
		while index < m_num_integers:
			let word = m_integers[index]
			if word != 0:
				let b = ctz(word)
				return index * n_bits_per_int + b
			index += 1
		panic("first: No bit set")

	pub fn iter() -> BitSetIter:
		let it = BitSetIter(m_bitset: this)
		it.init()
		it

pub class BitSetIter:
	var m_bitset: BitSet
	var m_slot: int = 0
	var m_word: int = 0

	pub fn init():
		m_slot = 0
		m_word = m_bitset.m_integers[m_slot]

	pub fn next() -> Option[int]:
		while m_slot < m_bitset.m_num_integers:
			if m_word != 0:
				let b = ctz(m_word)
				m_word = m_word & (m_word - 1)
				return Option.Some(m_slot * n_bits_per_int + b)

			# Next word:
			m_slot += 1
			if m_slot < m_bitset.m_num_integers:
				m_word = m_bitset.m_integers[m_slot]
			else:
				break

		Option.None()

let n_bits_per_int: int = 29

fn bit_mask(bit: int) -> int:
	1 << (bit % n_bits_per_int)

fn bit_slot(bit: int) -> int:
	bit / n_bits_per_int
