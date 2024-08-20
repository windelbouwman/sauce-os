
# Vector datatype.
# As opposed to the Linked List, we use an array here.
# The allocated array will be larger than the actual amount of values,
# and when appendingwe might need to re-allocate the array and copy
# the old values.

from utils import panic, assert, unimplemented
from datatypes import Option

fn new_vector[T](default: T) -> Vector[T]:
    return new_vector_with_capacity(default, capacity: 7)

fn new_vector_with_capacity[T](default: T, capacity: int) -> Vector[T]:
    let m_capacity = capacity
    let m_elements = [default : m_capacity]
    let v: Vector[T] = Vector(m_capacity, m_elements, m_default: default)
    return v

fn new_vector_of_size[T](size: int, default: T) -> Vector[T]:
    let m_capacity = size
    let m_elements = [default : m_capacity]
    let v: Vector[T] = Vector(m_capacity, m_elements, m_default: default)
    v.m_size = size
    return v

class Vector[T]:
    var m_size: int = 0
    var m_capacity: int
    var m_elements: [T]
    var m_default: T

    fn append(value?: T):
        if m_size == m_capacity:
            grow()
        m_elements[m_size] = value
        m_size += 1
    
    fn clear():
        m_size = 0

    fn grow():
        assert(condition: m_capacity > 0, message: "capacity must larger than zero.")
        let old_elements = m_elements
        m_capacity = m_capacity * 2
        m_elements = [m_default : m_capacity]
        # Copy old elements:
        let i = 0
        while i < m_size:
            m_elements[i] = old_elements[i]
            i += 1
        
    fn len() -> int:
        return m_size

    fn get(index: int) -> T:
        # Retrieve value at index
        if index < m_size:
            return m_elements[index]
        else:
            panic("Vector.get: index out of range.")
    
    fn set(index: int, value: T):
        # " Set value at index. "
        if index < m_size:
            m_elements[index] = value
        else:
            panic("Vector.get: index out of range.")
    
    fn last() -> T:
        return m_elements[m_size - 1]

    fn take(amount?: int) -> Vector[T]:
        # Create a new vector with the given amount of items
        assert(condition: amount < m_size, message: "take: amount must less than size.")
        let v2: Vector[T] = new_vector(default: m_default)
        let index = 0
        while index < amount:
            v2.append(get(index))
            index += 1
        return v2

    fn skip(amount?: int) -> Vector[T]:
        let v2: Vector[T] = new_vector(default: m_default)
        let index = amount
        while index < m_size:
            v2.append(get(index))
            index += 1
        return v2
    
    fn concat(other: Vector[T]) -> Vector[T]:
        let v2: Vector[T] = new_vector_with_capacity(default: m_default, capacity: m_size + other.m_size)
        
        let index = 0
        while index < m_size:
            v2.append(get(index))
            index += 1
        
        for value in other:
            v2.append(value)
        return v2
