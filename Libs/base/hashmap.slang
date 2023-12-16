
from datatypes import List, Option, DictionaryItem
from std import print, ord, str_len, str_get
from hashlib import elf_hash
from math import modulo

class HashMap[T]:
    # A list of association lists.
    # Association list is indexed by hash function
    var n_buckets: int = 0
    var n_rehash: int = 0
    var association_lists: List[AssociationList[T]] = List()

    fn get(key: str) -> Option[T]:
        if n_buckets > 0:
            let list = get_list(key)
            return list.get(key)
        else:
            return Option.None()
    
    fn get_list(key: str) -> AssociationList[T]:
        # let index = modulo(value: hash_key(key), divisor: n_buckets)
        let index = modulo(value: elf_hash(text: key), divisor: n_buckets)
        let list = association_lists.get(index)
        return list

    fn contains(key: str) -> bool:
        case get(key):
            Some(x):
                return true
            None:
                return false
    
    fn insert(key: str, value: T):
        if n_buckets == 0:
            # Start with 3 buckets:
            create_buckets(n: 3)
        else:
            n_rehash += 1
            if n_rehash > 100:
                # Check each 100 insertions if we need a rehash
                n_rehash = 0
                # print("Rehash?")

                let n_size = len()
                if n_size > 2 * n_buckets:
                    print("Rehash, len={n_size} buckets={n_buckets}")
                    let x = 0
                    for al in association_lists:
                        print("AL-{x}: {al.len()}")
                        x += 1
                        if x > 60:
                            break
                    rehash()
        # TODO: maybe rehash when lists get too long?
        let list = get_list(key)
        list.insert(key, value)
    
    fn len() -> int:
        let n = 0
        for al in association_lists:
            n += al.len()
        return n
    
    fn rehash():
        let old_association_lists = association_lists
        create_buckets(n: n_buckets * 2)  # Double the amount of buckets
        for al in old_association_lists:
            for item in al.items:
                let list = get_list(key: item.key)
                list.insert(key: item.key, value: item.value)
    
    fn create_buckets(n: int):
        n_buckets = n
        association_lists = List()
        while n > 0:
            n -= 1
            let new_list: AssociationList[T] = AssociationList()
            association_lists.append(new_list)
        print("Created {n_buckets} buckets")


class AssociationList[T]:
    var items: List[DictionaryItem[T]] = List()

    fn get(key: str) -> Option[T]:
        for item in items:
            if item.key == key:
                return Option.Some(item.value)
        return Option.None()

    fn insert(key: str, value: T):
        for item in items:
            if item.key == key:
                item.value = value
                return
        let new_item = DictionaryItem[T](key, value)
        items.append(new_item)
    
    fn len() -> int:
        return items.len()

fn hash_key(key: str) -> int:
    let hash = 0
    let i = 0
    let n = str_len(key)
    while i < n:
        hash += ord(str_get(text: key, index: i))
        i += 1
    return hash
