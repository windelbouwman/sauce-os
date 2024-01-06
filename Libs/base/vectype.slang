
# Vector datatype.
# As opposed to the Linked List, we use an array here.
# The allocated array will be larger than the actual amount of values,
# and when appendingwe might need to re-allocate the array and copy
# the old values.

from utils import panic, assert
from datatypes import Option

fn new_vector[T](default: T) -> Vector[T]:
    let m_capacity = 2
    let m_elements = [default : m_capacity]
    let v: Vector[T] = Vector(m_capacity, m_elements, m_default: default)
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
        return m_elements[index]
    
    fn set(index: int, value: T):
        # " Set value at index. "
        m_elements[index] = value

    fn iter() -> VectorIter[T]:
        return VectorIter(m_vector: this)

class VectorIter[T]:
    var m_vector: Vector[T]
    var m_index: int = 0

    fn next() -> Option[T]:
        if m_index < m_vector.m_size:
            let x = m_vector.m_elements[m_index]
            m_index += 1
            return Option.Some(x)
        else:
            return Option.None()
