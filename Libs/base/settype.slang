""" Set datatype, build upon the HashMap datatype.
"""

from datatypes import Option
from hashmap import HashMap, HashMapIter, new_hashmap, int_hash, int_eq, str_hash, str_eq

pub fn new_set[T](f_hash: fn(T) -> int, f_eq: fn(T,T) -> bool) -> Set[T]:
    let m_items = new_hashmap(f_hash, f_eq)
    Set(m_items)

pub fn new_str_set() -> Set[str]:
    new_set(f_hash: str_hash, f_eq: str_eq)

pub fn new_int_set() -> Set[int]:
    new_set(f_hash: int_hash, f_eq: int_eq)

pub class Set[T]:
    var m_items: HashMap[T, bool]

    pub fn add(value?: T):
        m_items.insert(key: value, value: true)

    pub fn contains(value?: T) -> bool:
        m_items.contains(key: value)

    pub fn remove(value?: T):
        let stub = m_items.pop(key: value)
    
    pub fn clear():
        m_items.clear()

    pub fn len() -> int:
        m_items.len()

    pub fn is_empty() -> bool:
        m_items.is_empty()

    pub fn iter() -> SetIter[T]:
        SetIter(m_it: m_items.iter())

pub class SetIter[T]:
    var m_it: HashMapIter[T, bool]

    pub fn next() -> Option[T]:
        m_it.next()
