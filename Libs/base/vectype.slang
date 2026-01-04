"""
Vector datatype.
As opposed to the Linked List, we use an array here.
The allocated array will be larger than the actual amount of values,
and when appendingwe might need to re-allocate the array and copy
the old values.
"""

from utils import panic, assert

pub fn new_vector[T]() -> Vector[T]:
	new_vector_with_capacity(capacity: 7)

pub fn new_vector_with_capacity[T](capacity: int) -> Vector[T]:
	let m_capacity = 1 if capacity < 1 else capacity
	let m_elements = [m_capacity : T]
	let v: Vector[T] = Vector(m_size: 0, m_capacity, m_elements)
	v

pub fn new_vector_of_size[T](size: int, default: T) -> Vector[T]:
	let m_capacity = size
	var m_elements = [m_capacity : T]
	var i = 0
	while i < size:
		m_elements[i] = default
		i += 1
	let v: Vector[T] = Vector(m_size: size, m_capacity, m_elements)
	v

pub fn vec1[T](v1?: T) -> Vector[T]:
	let vec: Vector[T] = new_vector_with_capacity(capacity: 1)
	vec.append(v1)
	vec

pub fn vec2[T](v1?: T, v2?: T) -> Vector[T]:
	let vec: Vector[T] = new_vector_with_capacity(capacity: 2)
	vec.append(v1)
	vec.append(v2)
	vec

pub fn vec3[T](v1?: T, v2?: T, v3?: T) -> Vector[T]:
	let vec: Vector[T] = new_vector_with_capacity(capacity: 3)
	vec.append(v1)
	vec.append(v2)
	vec.append(v3)
	vec

pub fn vec4[T](v1?: T, v2?: T, v3?: T, v4?: T) -> Vector[T]:
	let vec: Vector[T] = new_vector_with_capacity(capacity: 4)
	vec.append(v1)
	vec.append(v2)
	vec.append(v3)
	vec.append(v4)
	vec

pub fn vec5[T](v1?: T, v2?: T, v3?: T, v4?: T, v5?: T) -> Vector[T]:
	let vec: Vector[T] = new_vector_with_capacity(capacity: 5)
	vec.append(v1)
	vec.append(v2)
	vec.append(v3)
	vec.append(v4)
	vec.append(v5)
	vec

pub fn vec8[T](v1?: T, v2?: T, v3?: T, v4?: T, v5?: T, v6?: T, v7?: T, v8?: T) -> Vector[T]:
	let vec: Vector[T] = new_vector_with_capacity(capacity: 8)
	vec.append(v1)
	vec.append(v2)
	vec.append(v3)
	vec.append(v4)
	vec.append(v5)
	vec.append(v6)
	vec.append(v7)
	vec.append(v8)
	vec

pub class Vector[T]:
	var m_size: int
	var m_capacity: int
	var m_elements: [T]

	pub fn is_empty() -> bool:
		m_size == 0

	pub fn append(value?: T):
		if m_size == m_capacity:
			grow()
		m_elements[m_size] = value
		m_size += 1

	pub fn pop_last() -> T:
		if m_size > 0:
			m_size -= 1
			m_elements[m_size]
		else:
			panic("Vector.pop_last: empty vector")

	pub fn drop_last():
		drop_last_n(n: 1)

	pub fn drop_last_n(n: int):
		if m_size < n:
			panic("Vector.drop_last_n: dropping results in more than empty vector")
		else:
			m_size -= n

	pub fn extend(other?: Vector[T]):
		""" Append all elements of other to this vector """
		let new_size = m_size + other.len()
		while m_capacity < new_size:
			grow()
		var index = 0
		while index < other.len():
			m_elements[m_size] = other[index]
			m_size += 1
			index += 1

	pub fn clear():
		m_size = 0

	fn grow():
		assert(condition: m_capacity > 0, message: "capacity must larger than zero.")
		let old_elements = m_elements
		m_capacity = m_capacity * 2
		m_elements = [m_capacity : T]
		# Copy old elements:
		var i = 0
		while i < m_size:
			m_elements[i] = old_elements[i]
			i += 1

	pub fn len() -> int:
		m_size

	pub fn get(index: int) -> T:
		# Retrieve value at index
		if index < m_size:
			m_elements[index]
		else:
			panic("Vector.get: index out of range.")

	pub fn set(index: int, value: T):
		# " Set value at index. "
		if index < m_size:
			m_elements[index] = value
		else:
			panic("Vector.get: index out of range.")

	pub fn first() -> T:
		get(index: 0)

	pub fn last() -> T:
		m_elements[m_size - 1]

	pub fn take(amount?: int) -> Vector[T]:
		""" Create a new vector with the given amount of items """
		assert(condition: amount < m_size, message: "take: amount must less than size.")
		let v2: Vector[T] = new_vector()
		var index = 0
		while index < amount:
			v2.append(get(index))
			index += 1
		v2

	pub fn skip(amount?: int) -> Vector[T]:
		let v2: Vector[T] = new_vector()
		var index = amount
		while index < m_size:
			v2.append(get(index))
			index += 1
		v2

	pub fn concat(other: Vector[T]) -> Vector[T]:
		let v2: Vector[T] = new_vector_with_capacity(capacity: m_size + other.len())
		v2.extend(other: this)
		v2.extend(other)
		v2
