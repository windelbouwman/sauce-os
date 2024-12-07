""" Set datatype, build upon the dictionary datatype.
"""

from datatypes import Option
from dicttype import Dictionary, DictionaryIter
from hashmap import HashMap, HashMapIter, new_hashmap, int_hash, int_eq, str_hash, str_eq

fn new_set[T](f_hash: fn(T) -> int, f_eq: fn(T,T) -> bool) -> Set[T]:
    let m_items = new_hashmap(f_hash, f_eq)
    Set(m_items)

fn new_str_set() -> Set[str]:
    new_set(f_hash: str_hash, f_eq: str_eq)

fn new_int_set() -> Set[int]:
    new_set(f_hash: int_hash, f_eq: int_eq)

class Set[T]:
    var m_items: HashMap[T, bool]

    fn add(value?: T):
        m_items.insert(key: value, value: true)

    fn contains(value?: T) -> bool:
        m_items.contains(key: value)

    fn remove(value?: T):
        let stub = m_items.pop(key: value)

    fn len() -> int:
        m_items.len()

    fn is_empty() -> bool:
        m_items.is_empty()

    fn iter() -> SetIter[T]:
        SetIter(m_it: m_items.iter())

class SetIter[T]:
    var m_it: HashMapIter[T, bool]

    fn next() -> Option[T]:
        m_it.next()
