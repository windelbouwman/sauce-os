
# Set datatype, build upon the dictionary datatype.

from datatypes import Option
from dicttype import Dictionary, DictionaryIter

class StringSet:
    # Use a dictionary to emulate a set datatype.
    var items: Dictionary[bool] = Dictionary()

    fn add(value?: str):
        items.insert(key: value, value: true)
    
    fn remove(value?: str):
        let stub = items.pop(key: value)
    
    fn contains(value?: str) -> bool:
        return items.contains(key: value)

    fn is_empty() -> bool:
        return items.is_empty()

    fn iter() -> StringSetIter:
        let it = StringSetIter(it2: items.iter())
        return it


class StringSetIter:
    var it2: DictionaryIter[bool]

    fn next() -> Option[str]:
        return it2.next()


class IntegerSet:
    """ A type for a set of integers. """
    var m_string_set: StringSet = StringSet()

    fn add(value?: int):
        m_string_set.add(str(value))

    fn contains(value?: int) -> bool:
        return m_string_set.contains(str(value))
