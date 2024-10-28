""" Set datatype, build upon the dictionary datatype.
"""

from datatypes import Option
from dicttype import Dictionary, DictionaryIter

class StringSet:
    """ Use a dictionary to emulate a set datatype. """
    var items: Dictionary[bool] = Dictionary()

    fn add(value?: str):
        items.insert(key: value, value: true)
    
    fn remove(value?: str):
        let stub = items.pop(key: value)
    
    fn contains(value?: str) -> bool:
        items.contains(key: value)

    fn is_empty() -> bool:
        items.is_empty()

    fn iter() -> StringSetIter:
        StringSetIter(it2: items.iter())


class StringSetIter:
    var it2: DictionaryIter[bool]

    fn next() -> Option[str]:
        it2.next()


class IntegerSet:
    """ A type for a set of integers. """
    var m_string_set: StringSet = StringSet()

    fn add(value?: int):
        m_string_set.add(str(value))

    fn contains(value?: int) -> bool:
        m_string_set.contains(str(value))
