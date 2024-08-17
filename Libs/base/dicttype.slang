
# The dictionary datatype.
# Two implementation options:
# - An association list
# - A hashmap

from datatypes import List, ListIter
from datatypes import Option, option_unwrap
from hashmap import HashMap, HashMapIter
from assoclist import AssociationList, AssociationListIter

class Dictionary[T]:
    # var items: AssociationList[T] = AssociationList()
    # Or, use a hashmap:
    var items: HashMap[T] = HashMap()

    fn get(key: str) -> T:
        return option_unwrap(maybe_get(key))

    fn maybe_get(key: str) -> Option[T]:
        return items.maybe_get(key)
    
    fn is_empty() -> bool:
        return items.is_empty()
    
    fn clear():
        items.clear()

    fn contains(key: str) -> bool:
        case maybe_get(key):
            Some(x):
                return true
            None:
                return false

    fn insert(key: str, value: T):
        items.insert(key, value)
    
    fn pop(key: str) -> Option[T]:
        # remove an item from this dictionary
        return items.pop(key)

    fn values() -> List[T]:
        return items.values()

    fn iter() -> DictionaryIter[T]:
        let it = DictionaryIter(it2: items.iter())
        return it

class DictionaryIter[T]:
    var it2: HashMapIter[T]
    # var it2: AssociationListIter[T]

    fn next() -> Option[str]:
        return it2.next()

