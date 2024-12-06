"""
Hash map data type.

Idea: have an array with buckets.
"""

from datatypes import List, ListIter, Option, option_unwrap, option_is_some
from std import print
from utils import panic
from rt import str_compare
from hashlib import djb2
from math import modulo

fn new_hashmap_int[V]() -> HashMap[int,V]:
    """ Create a new hashmap with integer keys """
    new_hashmap(f_hash: int_hash, f_eq: int_compare)

fn new_hashmap_str[V]() -> HashMap[str,V]:
    """ Create a new hashmap with string keys """
    new_hashmap(f_hash: djb2, f_eq: str_compare)

fn new_hashmap[K,V](f_hash: fn(K) -> int, f_eq: fn(K, K) -> bool) -> HashMap[K,V]:
    let m: HashMap[K,V] = HashMap(f: HashableApi(f_hash, f_eq))
    m.create_buckets(n: 16)
    m

fn int_compare(a: int, b: int) -> bool:
    a == b

fn int_hash(x: int) -> int:
    x

class HashMap[K,V]:
    # A list of association lists.
    # Association list is indexed by hash function
    var num_buckets: int = 0
    var m_threshold: int = 0
    var m_size: int = 0
    var m_buckets: [List[KeyValuePair[K,V]]] = [List()]
    var f: HashableApi[K]

    fn maybe_get(key: K) -> Option[V]:
        let list = get_list(key)
        for pair in list:
            if f.f_eq(pair.key, key):
                return Option.Some(pair.value)
        Option.None()

    fn get_list(key: K) -> List[KeyValuePair[K,V]]:
        if num_buckets == 0:
            panic("Uninitialized hashmap!")
        let index = modulo(value: this.f.f_hash(key), divisor: num_buckets)
        let list = m_buckets[index]
        list

    fn contains(key: K) -> bool:
        option_is_some(maybe_get(key))
    
    fn get(key: K) -> V:
        option_unwrap(maybe_get(key))

    fn insert(key: K, value: V):
        # Re-hash if above some threshold
        if m_size > m_threshold:
            rehash()

        let list = get_list(key)
        for item in list:
            if f.f_eq(item.key, key):
                item.value = value
                return
        let pair: KeyValuePair[K,V] = KeyValuePair(key, value)
        list.append(pair)
        m_size += 1

    fn pop(key: K) -> Option[V]:
        """ remove an item from this dictionary """
        let list = get_list(key)

        let index = 0
        for item in list:
            if f.f_eq(item.key, key):
                # patch list:
                list.delete_at(index)
                m_size -= 1
                return Option.Some(item.value)
            index += 1

        return Option.None()

    fn debug_display():
        print("n_buckets={num_buckets}")
        let x = 0
        let i = 0
        while i < num_buckets:
            let b = m_buckets[i]
            print("  bucket-{x}: {b.len()}")
            x += 1
            if x > 30:
                break
            i += 1

    fn len() -> int:
        m_size
    
    fn clear():
        let i = 0
        while i < num_buckets:
            m_buckets[i].clear()
            i += 1
        m_size = 0

    fn is_empty() -> bool:
        m_size == 0
    
    fn rehash():
        let old_buckets = m_buckets
        let old_n_buckets = num_buckets
        # Double the amount of buckets:
        create_buckets(n: num_buckets * 2)
        let i = 0
        while i < old_n_buckets:
            let b = old_buckets[i]
            for pair in b:
                insert(key: pair.key, value: pair.value)
            i += 1
    
    fn create_buckets(n: int):
        num_buckets = n
        m_threshold = (n * 3) / 4  # Rehash at load factor of 75%
        m_buckets = [n : List[KeyValuePair[K,V]]]
        let i = 0
        while i < n:
            let new_list: List[KeyValuePair[K,V]] = List()
            m_buckets[i] = new_list
            i += 1
        m_size = 0

    fn values() -> List[V]:
        let res: List[V] = List()

        let i = 0
        while i < num_buckets:
            for v in m_buckets[i]:
                res.append(v.value)
            i += 1
        res

    fn iter() -> HashMapIter[K,V]:
        let it: HashMapIter[K,V] = HashMapIter(m: this)
        it

class HashMapIter[K,V]:
    var index: int = 0
    var it2: Option[ListIter[KeyValuePair[K,V]]] = Option.None()
    var m: HashMap[K,V]

    fn next() -> Option[K]:
        loop:
            case it2:
                Some(it3):
                    case it3.next():
                        Some(v):
                            return Option.Some(v.key)
                        None:
                            it2 = Option.None()
                None:
                    # Get next iterator!
                    if index < m.num_buckets:
                        it2 = Option.Some(m.m_buckets[index].iter())
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
