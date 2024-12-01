
# Hash map data type.
# Idea: have an array with buckets.

from datatypes import List, Option, option_unwrap
from assoclist import AssociationList, AssociationListIter, HashableApi
from std import print, ord
from rt import str_compare
from hashlib import djb2
from math import modulo

fn int_compare(a: int, b: int) -> bool:
    a == b

fn int_hash(x: int) -> int:
    x

class HashMapInt[T]:
    var m_inner: HashMap2[int, T] = HashMap2(f: HashableApi(f_hash: int_hash, f_eq: int_compare))

    fn is_empty() -> bool:
        m_inner.is_empty()
    
    fn len() -> int:
        m_inner.len()

    fn clear():
        m_inner.clear()
    
    fn contains(key: int) -> bool:
        m_inner.contains(key)

    fn insert(key: int, value: T):
        m_inner.insert(key, value)

    fn get(key: int) -> T:
        m_inner.get(key)

class HashMapStr[T]:
    var m_inner: HashMap2[str, T] = HashMap2(f: HashableApi(f_hash: djb2, f_eq: str_compare))

    fn maybe_get(key: str) -> Option[T]:
        m_inner.maybe_get(key)
    
    fn is_empty() -> bool:
        m_inner.is_empty()
    
    fn len() -> int:
        m_inner.len()

    fn clear():
        m_inner.clear()
    
    fn contains(key: str) -> bool:
        m_inner.contains(key)

    fn insert(key: str, value: T):
        m_inner.insert(key, value)

    fn pop(key: str) -> Option[T]:
        m_inner.pop(key)

    fn values() -> List[T]:
        m_inner.values()
    
    fn iter() -> HashMapStrIter[T]:
        HashMapStrIter(m_inner: m_inner.iter())
    
    fn get(key: str) -> T:
        m_inner.get(key)

class HashMapStrIter[T]:
    var m_inner: HashMap2Iter[str, T]

    fn next() -> Option[str]:
        m_inner.next()

class HashMap2[K,V]:
    # A list of association lists.
    # Association list is indexed by hash function
    var n_buckets: int = 0
    var n_rehash: int = 0
    var buckets: [AssociationList[K,V]] = [AssociationList()]
    var f: HashableApi[K]

    fn maybe_get(key: K) -> Option[V]:
        if n_buckets > 0:
            let list = get_list(key)
            list.maybe_get(key, f_eq: f.f_eq)
        else:
            Option.None()
    
    fn get_list(key: K) -> AssociationList[K,V]:
        # let index = modulo(value: hash_key(key), divisor: n_buckets)
        let index = modulo(value: this.f.f_hash(key), divisor: n_buckets)
        let list = buckets[index]
        list

    fn contains(key: K) -> bool:
        case maybe_get(key):
            Some(x):
                true
            None:
                false
    
    fn get(key: K) -> V:
        option_unwrap(maybe_get(key))

    fn insert(key: K, value: V):
        if n_buckets == 0:
            # Start with 3 buckets:
            create_buckets(n: 3)
        else:
            n_rehash += 1
            if n_rehash > 2000:
                # Check each n insertions if we need a rehash
                # debug_display()
                n_rehash = 0
                # print("Rehash?")

                let n_size = len()
                if n_size > 2 * n_buckets:
                    rehash()
        # TODO: maybe rehash when lists get too long?
        let list = get_list(key)
        list.insert(key, value, f_eq: f.f_eq)

    fn pop(key: K) -> Option[V]:
        # remove an item from this dictionary
        let list = get_list(key)
        list.pop(key, f_eq: f.f_eq)

    fn debug_display():
        print("n_buckets={n_buckets}")
        let x = 0
        let i = 0
        while i < n_buckets:
            let b = buckets[i]
            print("  bucket-{x}: {b.len()}")
            x += 1
            if x > 30:
                break
            i += 1

    fn len() -> int:
        let n = 0
        let i = 0
        while i < n_buckets:
            n += buckets[i].len()
            i += 1
        n
    
    fn clear():
        let i = 0
        while i < n_buckets:
            buckets[i].clear()
            i += 1
    
    fn is_empty() -> bool:
        let i = 0
        while i < n_buckets:
            if not buckets[i].is_empty():
                return false
            i += 1
        true
    
    fn rehash():
        let old_buckets = buckets
        let old_n_buckets = n_buckets
        # Double the amount of buckets:
        create_buckets(n: n_buckets * 2)
        let i = 0
        while i < old_n_buckets:
            let b = old_buckets[i]
            for item in b.items:
                let list = get_list(key: item.key)
                list.insert(key: item.key, value: item.value, f_eq: f.f_eq)
            i += 1
    
    fn create_buckets(n: int):
        n_buckets = n
        buckets = [n : AssociationList[K,V]]
        let i = 0
        while i < n:
            let new_list: AssociationList[K,V] = AssociationList()
            buckets[i] = new_list
            i += 1
        # print("Created {n_buckets} buckets")

    fn values() -> List[V]:
        let res: List[V] = List()

        let i = 0
        while i < n_buckets:
            for v in buckets[i].items:
                res.append(v.value)
            i += 1

        res

    fn iter() -> HashMap2Iter[K,V]:
        let it: HashMap2Iter[K,V] = HashMap2Iter(m: this)
        it


class HashMap2Iter[K,V]:
    var index: int = 0
    var it2: Option[AssociationListIter[K,V]] = Option.None()
    var m: HashMap2[K,V]

    fn next() -> Option[K]:
        loop:
            case it2:
                Some(it3):
                    case it3.next():
                        Some(v):
                            return Option.Some(v)
                        None:
                            it2 = Option.None()
                None:
                    # Get next iterator!
                    if index < m.n_buckets:
                        it2 = Option.Some(m.buckets[index].iter())
                        index += 1
                    else:
                        break

        return Option.None()
