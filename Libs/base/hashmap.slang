"""
Hash map data type.

Idea: have an array with buckets.
"""

from datatypes import Option, option_unwrap, option_is_some
from datatypes import List
from std import print, ord
from utils import panic
from rt import str_compare
from hashlib import djb2
from math import modulo

pub fn new_hashmap_int[V]() -> HashMap[int,V]:
    """ Create a new hashmap with integer keys """
    new_hashmap(f_hash: int_hash, f_eq: int_eq)

pub fn new_hashmap_str[V]() -> HashMap[str,V]:
    """ Create a new hashmap with string keys """
    new_hashmap(f_hash: str_hash, f_eq: str_eq)

pub fn new_hashmap_char[V]() -> HashMap[char,V]:
    """ Create a new hashmap with char keys """
    new_hashmap(f_hash: char_hash, f_eq: char_eq)

pub fn new_hashmap[K,V](f_hash: fn(K) -> int, f_eq: fn(K, K) -> bool) -> HashMap[K,V]:
    let m: HashMap[K,V] = HashMap(f: HashableApi(f_hash, f_eq))
    m.create_buckets(n: 16)
    m

pub fn str_hash(text?: str) -> int:
    djb2(text)

pub fn str_eq(a?: str, b?: str) -> bool:
    str_compare(a, b)

pub fn int_eq(a: int, b: int) -> bool:
    a == b

pub fn int_hash(x: int) -> int:
    x

pub fn char_eq(a: char, b: char) -> bool:
    a == b

pub fn char_hash(x: char) -> int:
    ord(x)

pub class HashMap[K,V]:
    var num_buckets: int = 0
    var m_threshold: int = 0
    var m_size: int = 0
    var m_buckets: [Option[KeyValuePair[K,V]]] = [Option.None()]
    var f: HashableApi[K]

    pub fn maybe_get(key: K) -> Option[V]:
        let next_pair = m_buckets[get_index(key)]
        loop:
            case next_pair:
                Some(pair):
                    if f.f_eq(pair.key, key):
                        return Option.Some(pair.value)
                    else:
                        next_pair = pair.next
                None:
                    break
        Option.None()

    fn get_index(key: K) -> int:
        if num_buckets == 0:
            panic("Uninitialized hashmap!")
        let value = this.f.f_hash(key)
        if value < 0:
            value = -value
        modulo(value, divisor: num_buckets)

    pub fn contains(key: K) -> bool:
        option_is_some(maybe_get(key))
    
    pub fn get(key: K) -> V:
        option_unwrap(maybe_get(key))

    pub fn insert(key: K, value: V):
        # Re-hash if above some threshold
        if m_size > m_threshold:
            rehash()

        let index = get_index(key)

        # Search for key in bucket:
        let last_pair_ptr: Option[KeyValuePair[K,V]] = Option.None()
        let pair_ptr = m_buckets[index]
        loop:
            case pair_ptr:
                Some(pair):
                    if f.f_eq(pair.key, key):
                        pair.value = value
                        return
                    else:
                        last_pair_ptr = pair_ptr
                        pair_ptr = pair.next
                None:
                    break

        # Append new pair:
        let new_pair: Option[KeyValuePair[K,V]] = Option.Some(KeyValuePair(key, value, next: Option.None()))
        case last_pair_ptr:
            Some(last_pair):
                last_pair.next = new_pair
            None:
                m_buckets[index] = new_pair
        m_size += 1

    pub fn pop(key: K) -> Option[V]:
        """ remove an item from this dictionary """
        let index = get_index(key)

        # Search for key in bucket:
        let last_pair_ptr: Option[KeyValuePair[K,V]] = Option.None()
        let pair_ptr = m_buckets[index]
        loop:
            case pair_ptr:
                Some(pair):
                    if f.f_eq(pair.key, key):
                        # patch linked list:
                        case last_pair_ptr:
                            Some(last_pair):
                                last_pair.next = pair.next
                            None:
                                m_buckets[index] = pair.next
                        m_size -= 1
                        return Option.Some(pair.value)
                    else:
                        last_pair_ptr = pair_ptr
                        pair_ptr = pair.next
                None:
                    break
        Option.None()

    fn debug_display():
        print("n_buckets={num_buckets}")
        # let x = 0
        # let i = 0
        # while i < num_buckets:
        #     let b = m_buckets[i]
        #     print("  bucket-{x}: {b.len()}")
        #     x += 1
        #     if x > 30:
        #         break
        #     i += 1

    pub fn len() -> int:
        m_size
    
    pub fn clear():
        create_buckets(n: num_buckets)

    pub fn is_empty() -> bool:
        m_size == 0

    fn rehash():
        let old_buckets = m_buckets
        let old_n_buckets = num_buckets
        # Double the amount of buckets:
        create_buckets(n: num_buckets * 2)

        # Insert existing pairs:
        let i = 0
        while i < old_n_buckets:
            let pair_ptr = old_buckets[i]
            loop:
                case pair_ptr:
                    Some(pair):
                        insert(key: pair.key, value: pair.value)
                        pair_ptr = pair.next
                    None:
                        break
            i += 1
    
    fn create_buckets(n: int):
        num_buckets = n
        m_threshold = (n * 3) / 4  # Rehash at load factor of 75%
        m_buckets = [n : Option[KeyValuePair[K,V]]]
        let i = 0
        while i < n:
            m_buckets[i] = Option.None()
            i += 1
        m_size = 0

    pub fn values() -> List[V]:
        let res: List[V] = List()

        let i = 0
        while i < num_buckets:
            let pair_ptr = m_buckets[i]
            loop:
                case pair_ptr:
                    Some(pair):
                        res.append(pair.value)
                        pair_ptr = pair.next
                    None:
                        break
            i += 1
        res

    pub fn iter() -> HashMapIter[K,V]:
        let it: HashMapIter[K,V] = HashMapIter(m: this)
        it

pub class HashMapIter[K,V]:
    var index: int = 0
    var m_pair_ptr: Option[KeyValuePair[K,V]] = Option.None()
    var m: HashMap[K,V]

    pub fn next() -> Option[K]:
        loop:
            case m_pair_ptr:
                Some(pair):
                    m_pair_ptr = pair.next
                    return Option.Some(pair.key)
                None:
                    # Get next iterator!
                    if index < m.num_buckets:
                        m_pair_ptr = m.m_buckets[index]
                        index += 1
                    else:
                        break

        return Option.None()

struct HashableApi[T]:
    f_hash: fn(T) -> int
    f_eq: fn(T,T) -> bool

struct KeyValuePair[K,V]:
    key: K
    value: V
    next: Option[KeyValuePair[K,V]]
