
# TODO: implement array of array deque
# See: https://www.youtube.com/watch?v=CXfvQ_ClgSM

from utils import panic, assert

pub fn new_queue[T]() -> Queue[T]:
	new_queue_with_capacity(capacity: 7)

pub fn new_queue_with_capacity[T](capacity: int) -> Queue[T]:
	assert(condition: capacity > 0, message: "capacity must larger than zero.")
	Queue(m_items: [capacity : T], m_capacity: capacity)

pub class Queue[T]:
	""" Implement a FIFO queue data type """
	var m_items: [T]
	var m_capacity: int
	var m_length: int = 0
	var m_head: int = 0
	var m_tail: int = 0

	pub fn push(value?: T):
		""" Append a value to the queue """
		if m_length < m_capacity:
			m_items[m_tail] = value
			m_tail = inc(m_tail)
			m_length += 1
		else:
			grow()
			push(value)

	pub fn pop() -> T:
		""" Pop first value from the queue """
		if m_length > 0:
			let value = m_items[m_head]
			m_head = inc(m_head)
			m_length -= 1
			value
		else:
			panic("Pop from empty queue")

	pub fn clear():
		m_length = 0
		m_head = 0
		m_tail = 0

	pub fn len() -> int:
		m_length

	pub fn is_empty() -> bool:
		m_length == 0

	fn grow():
		assert(condition: m_capacity > 0, message: "capacity must larger than zero.")

		let new_capacity = m_capacity * 2
		var new_items = [new_capacity : T]

		# Populate new items:
		m_tail = 0
		while m_tail < m_length:
			new_items[m_tail] = m_items[m_head]
			m_head = inc(m_head)
			m_tail += 1

		# Update
		m_items = new_items
		m_capacity = new_capacity
		m_head = 0

	fn inc(value?: int) -> int:
		value += 1
		if value < m_capacity:
			value
		else:
			0
