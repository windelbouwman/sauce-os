
# Hash map data type.
# Idea: have an array with buckets.

from utils import panic
from datatypes import List, ListIter, Option, option_unwrap
from assoclist import AssociationList, AssociationListIter
from std import print, ord, str_len, str_get
from hashlib import elf_hash
from math import modulo

class HashMap[T]:
    # A list of association lists.
    # Association list is indexed by hash function
    var n_buckets: int = 1
    var n_rehash: int = 0
    var buckets: [AssociationList[T]] = [AssociationList()]

    fn maybe_get(key: str) -> Option[T]:
        if n_buckets > 0:
            let list = get_list(key)
            return list.maybe_get(key)
        else:
            return Option.None()
    
    fn get_list(key: str) -> AssociationList[T]:
        # let index = modulo(value: hash_key(key), divisor: n_buckets)
        let index = modulo(value: elf_hash(text: key), divisor: n_buckets)
        let list = buckets[index]
        return list

    fn contains(key: str) -> bool:
        case maybe_get(key):
            Some(x):
                return true
            None:
                return false
    
    fn get(key: str) -> T:
        return option_unwrap(maybe_get(key))

    fn insert(key: str, value: T):
        if n_buckets == 0:
            # Start with 3 buckets:
            create_buckets(n: 3)
        else:
            n_rehash += 1
            if n_rehash > 5:
                # Check each n insertions if we need a rehash
                # debug_display()
                n_rehash = 0
                # print("Rehash?")

                let n_size = len()
                if n_size > 2 * n_buckets:
                    rehash()
        # TODO: maybe rehash when lists get too long?
        let list = get_list(key)
        list.insert(key, value)

    fn pop(key: str) -> Option[T]:
        # remove an item from this dictionary
        let list = get_list(key)
        return list.pop(key)

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
        return n
    
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
        return true
    
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
                list.insert(key: item.key, value: item.value)
            i += 1
    
    fn create_buckets(n: int):
        n_buckets = n
        buckets = [n : AssociationList[T]]
        let i = 0
        while i < n:
            let new_list: AssociationList[T] = AssociationList()
            buckets[i] = new_list
            i += 1
        # print("Created {n_buckets} buckets")

    fn values() -> List[T]:
        let res: List[T] = List()

        let i = 0
        while i < n_buckets:
            for v in buckets[i].items:
                res.append(v.value)
            i += 1

        return res

    fn iter() -> HashMapIter[T]:
        let it: HashMapIter[T] = HashMapIter(m: this)
        return it



fn hash_key(key: str) -> int:
    let hash = 0
    let i = 0
    let n = str_len(text: key)
    while i < n:
        hash += ord(str_get(text: key, index: i))
        i += 1
    return hash

class HashMapIter[T]:
    var index: int = 0
    var it2: Option[AssociationListIter[T]] = Option.None()
    var m: HashMap[T]

    fn next() -> Option[str]:
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
                        # panic("TODO")
                    else:
                        break

        return Option.None()
