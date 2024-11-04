
# Association list datatype.
# Most simple dictionary implementation: a list of key value pairs.
from datatypes import List, ListIter, Option, option_unwrap

class AssociationList[T]:
    var items: List[AssociationListItem[T]] = List()

    fn insert(key: str, value: T):
        for item in items:
            if item.key == key:
                item.value = value
                return
        let new_item = AssociationListItem[T](key, value)
        items.append(new_item)

    fn get(key: str) -> T:
        option_unwrap(maybe_get(key))

    fn maybe_get(key: str) -> Option[T]:
        for item in items:
            if item.key == key:
                return Option.Some(item.value)
        Option.None()

    fn pop(key: str) -> Option[T]:
        # remove an item from this dictionary
        let index = 0
        for item in items:
            if item.key == key:
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

    fn iter() -> AssociationListIter[T]:
        let it = AssociationListIter(it2: items.iter())
        it

struct AssociationListItem[T]:
    key: str
    value: T

class AssociationListIter[T]:
    var it2: ListIter[AssociationListItem[T]]

    fn next() -> Option[str]:
        case it2.next():
            None:
                Option.None()
            Some(i):
                Option.Some(i.key)

