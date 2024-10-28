
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
        option_unwrap(maybe_get(key))

    fn maybe_get(key: str) -> Option[T]:
        items.maybe_get(key)
    
    fn is_empty() -> bool:
        items.is_empty()
    
    fn clear():
        items.clear()

    fn contains(key: str) -> bool:
        case maybe_get(key):
            Some(x):
                true
            None:
                false

    fn insert(key: str, value: T):
        items.insert(key, value)
    
    fn pop(key: str) -> Option[T]:
        # remove an item from this dictionary
        items.pop(key)

    fn values() -> List[T]:
        items.values()

    fn iter() -> DictionaryIter[T]:
        DictionaryIter(it2: items.iter())

class DictionaryIter[T]:
    var it2: HashMapIter[T]
    # var it2: AssociationListIter[T]

    fn next() -> Option[str]:
        it2.next()

