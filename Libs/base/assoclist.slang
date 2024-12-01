
# Association list datatype.
# Most simple dictionary implementation: a list of key value pairs.
from datatypes import List, ListIter, Option, option_unwrap

struct HashableApi[T]:
    f_hash: fn(T) -> int
    f_eq: fn(T,T) -> bool

class AssociationList[K, V]:
    var items: List[AssociationListItem[K,V]] = List()

    fn insert(key: K, value: V, f_eq: fn(K,K) -> bool):
        for item in items:
            if f_eq(item.key, key):
                item.value = value
                return
        let new_item: AssociationListItem[K,V] = AssociationListItem(key, value)
        items.append(new_item)

    fn get(key: K, f_eq: fn(K,K) -> bool) -> V:
        option_unwrap(maybe_get(key, f_eq))

    fn maybe_get(key: K, f_eq: fn(K,K) -> bool) -> Option[V]:
        for item in items:
            if f_eq(item.key, key):
                return Option.Some(item.value)
        Option.None()

    fn pop(key: K, f_eq: fn(K,K) -> bool) -> Option[V]:
        # remove an item from this dictionary
        let index = 0
        for item in items:
            if f_eq(item.key, key):
                # patch list:
                items.delete_at(index)
                return Option.Some(item.value)
            index += 1

        return Option.None()

    fn len() -> int:
        items.len()

    fn is_empty() -> bool:
        items.is_empty()
    
    fn clear():
        items.clear()

    fn iter() -> AssociationListIter[K,V]:
        let it = AssociationListIter(it2: items.iter())
        it

struct AssociationListItem[K,V]:
    key: K
    value: V

class AssociationListIter[K,V]:
    var it2: ListIter[AssociationListItem[K,V]]

    fn next() -> Option[K]:
        case it2.next():
            None:
                Option.None()
            Some(i):
                Option.Some(i.key)
