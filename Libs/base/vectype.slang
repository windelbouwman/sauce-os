
# Vector datatype.
# As opposed to the Linked List, we use an array here.
# The allocated array will be larger than the actual amount of values,
# and when appendingwe might need to re-allocate the array and copy
# the old values.

from utils import panic, assert, unimplemented
from datatypes import Option

fn new_vector[T](default: T) -> Vector[T]:
    let m_capacity = 2
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
        assert(condition: index < m_size, message: "Vector.get: index out of range.")
        return m_elements[index]
    
    fn set(index: int, value: T):
        # " Set value at index. "
        assert(condition: index < m_size, message: "Vector.get: index out of range.")
        m_elements[index] = value
    
    fn last() -> T:
        return m_elements[m_size - 1]

    fn iter() -> VectorIter[T]:
        return VectorIter(m_vector: this)

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
        let v2: Vector[T] = new_vector(default: m_default)
        
        let index = 0
        while index < m_size:
            v2.append(get(index))
            index += 1
        
        index = 0
        while index < other.m_size:
            v2.append(other.get(index))
            index += 1
        return v2


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
