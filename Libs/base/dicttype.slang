
# The dictionary datatype.
# Two implementation options:
# - An association list
# - A hashmap

from datatypes import List
from datatypes import Option, option_unwrap
from hashmap import HashMap, new_hashmap_str, HashMapIter

class Dictionary[T]:
    var items: HashMap[str, T] = new_hashmap_str()

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
    
    fn len() -> int:
        items.len()

    fn iter() -> DictionaryIter[T]:
        DictionaryIter(it2: items.iter())

class DictionaryIter[T]:
    var it2: HashMapIter[str, T]

    fn next() -> Option[str]:
        it2.next()
