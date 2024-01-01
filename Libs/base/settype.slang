
# Set datatype, build upon the dictionary datatype.

from datatypes import Option
from dicttype import Dictionary, DictionaryIter


class Set:
    # Use a dictionary to emulate a set datatype.
    var items: Dictionary[int] = Dictionary()

    fn add(value?: str):
        items.insert(key: value, value: 1)
    
    fn remove(value?: str):
        let stub = items.pop(key: value)
    
    fn contains(value?: str) -> bool:
        return items.contains(key: value)

    fn is_empty() -> bool:
        return items.is_empty()

    fn iter() -> SetIter:
        let it = SetIter(it2: items.iter())
        return it


class SetIter:
    var it2: DictionaryIter[int]

    fn next() -> Option[str]:
        return it2.next()

