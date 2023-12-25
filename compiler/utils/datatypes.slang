
from utils import panic
from std import str_len, str_slice, str_get

enum Option[D]:
    Some(value?: D)
    None

fn option_unwrap[T](option?: Option[T]) -> T:
    case option:
        Some(value):
            return value
        None:
            panic("Cannot unwrap None")

fn option_unwrap_or[T](option: Option[T], default: T) -> T:
    case option:
        Some(value):
            return value
        None:
            return default

fn option_is_some[T](opt?: Option[T]) -> bool:
    case opt:
        Some(v):
            return true
        None:
            return false

fn option_is_none[T](opt?: Option[T]) -> bool:
    case opt:
        Some(v):
            return false
        None:
            return true

enum Result[O,E]:
    Ok(value: O)
    Error(value: E)

fn vec1[T](v1?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    return vec

fn vec2[T](v1?: T, v2?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec.append(v2)
    return vec

fn vec3[T](v1?: T, v2?: T, v3?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec.append(v2)
    vec.append(v3)
    return vec

fn vec4[T](v1?: T, v2?: T, v3?: T, v4?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec.append(v2)
    vec.append(v3)
    vec.append(v4)
    return vec

fn vec5[T](v1?: T, v2?: T, v3?: T, v4?: T, v5?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec.append(v2)
    vec.append(v3)
    vec.append(v4)
    vec.append(v5)
    return vec

class List[T]:
    # Linked list based on a linked list of elements with next pointers.

    var head_element: Option[ListElement[T]] = Option.None()

    fn append(val?: T):
        let new_tail_element = ListElement[T]:
            next: Option.None()
            data: val

        case head_element:
            None:
                head_element = Option.Some(new_tail_element)
            Some(element):
                loop:
                    case element.next:
                        None:
                            break
                        Some(nxt_element):
                            element = nxt_element
                element.next = Option.Some(new_tail_element)

    fn prepend(val?: T):
        # Prepend value in front of list
        let new_head_element = ListElement[T](next: head_element, data: val)
        head_element = Option.Some(new_head_element)

    fn is_empty() -> bool:
        case head_element:
            None:
                return true
        else:
            return false

    fn len() -> int:
        # Retrieve length of the list
        case head_element:
            None:
                return 0
            Some(element):
                let n = 1
                loop:
                    case element.next:
                        None:
                            break
                        Some(nxt_element2):
                            element = nxt_element2
                            n += 1
                return n

    fn clear():
        while not is_empty():
            let dummy = pop_front()

    fn pop_front() -> T:
        case head_element:
            None:
                panic("List.pop_front from empty list!")
            Some(element):
                head_element = element.next
                return element.data

    fn iter() -> ListIter[T]:
        let it = ListIter()
        it.next_element = head_element
        return it

    fn first() -> T:
        # Retrieve first element
        case head_element:
            None:
                panic("List.first on empty list!")
            Some(element):
                return element.data

    fn drop_last():
        # Drop last item from list
        let x = pop_last()

    fn pop_last() -> T:
        # Pop last element of the list
        case head_element:
            None:
                panic("List.pop_last from empty list!")
            Some(element):
                case element.next:
                    None:
                        # single item in list!
                        head_element = Option.None()
                        return element.data
                    Some(next_element):
                        # More than 1 item in the list

                        loop:
                            case next_element.next:
                                None:
                                    # This is the last item!
                                    element.next = Option.None()
                                    return next_element.data
                                Some(next_next_element):
                                    # Slide to next item
                                    element = next_element
                                    next_element = next_next_element
                        panic("pop_last: Should not get here.")

    fn last() -> T:
        # Retrieve last element
        case head_element:
            None:
                panic("List.last on empty list!")
            Some(element):
                loop:
                    case element.next:
                        None:
                            break
                        Some(nxt_element2):
                            element = nxt_element2
                return element.data
    
    fn get(index: int) -> T:
        # Retrieve value at index
        let element = get_element(index)
        return element.data
    
    fn set(index: int, value: T):
        # " Set value at index. "
        let element = get_element(index)
        element.data = value
    
    fn get_element(index: int) -> ListElement[T]:
        case head_element:
            None:
                panic("List.get on empty list!")
            Some(element):
                let n = 0
                loop:
                    if n == index:
                        return element

                    case element.next:
                        None:
                            break
                        Some(nxt_element2):
                            element = nxt_element2
                    n = n + 1
                panic("List.get_element index out of range!")

    fn delete_at(index: int):
        # remove item at index from list
        case head_element:
            None:
                panic("List.delete_at on empty list!")
            Some(element):
                let n = 0
                let prev_element: Option[ListElement[T]] = Option.None()
                loop:
                    if n == index:
                        case prev_element:
                            Some(pe):
                                pe.next = element.next
                            None:
                                head_element = element.next
                        return

                    case element.next:
                        None:
                            panic("List.delete_at index out of range!")
                            break
                        Some(nxt_element2):
                            prev_element = Option.Some(element)
                            element = nxt_element2
                    n += 1

    fn reversed() -> List[T]:
        # Return a reversed list
        let result: List[T] = List()
        for value in this:
            result.prepend(value)
        return result
    
    fn extend(other?: List[T]):
        while not other.is_empty():
            append(other.pop_front())
    #fn filter():
    #    pass

struct ListElement[T]:
    next: Option[ListElement[T]]
    data: T

class ListIter[T]:
    var next_element: Option[ListElement[T]] = Option.None()

    fn next() -> Option[T]:
        let opt = next_element
        case opt:
            None:
                return Option.None()
            Some(nxt_element):
                let x = Option.Some(nxt_element.data)
                next_element = nxt_element.next
                return x


class Dictionary[T]:
    var items: List[DictionaryItem[T]] = List()

    fn get(key: str) -> Option[T]:
        for item in items:
            if item.key == key:
                return Option.Some(item.value)
        return Option.None()
    
    fn is_empty() -> bool:
        return items.is_empty()

    fn contains(key: str) -> bool:
        case get(key):
            Some(x):
                return true
            None:
                return false
    
    fn insert(key: str, value: T):
        for item in items:
            if item.key == key:
                item.value = value
                return
        let new_item = DictionaryItem[T](key, value)
        items.append(new_item)
    
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

    fn iter() -> DictionaryIter:
        let it = DictionaryIter()
        it.it2 = items.iter()
        return it

struct DictionaryItem[T]:
    key: str
    value: T

class DictionaryIter[T]:
    var it2: ListIter[DictionaryItem[T]] = ListIter()

    fn next() -> Option[str]:
        case it2.next():
            None:
                return Option.None()
            Some(i):
                return Option.Some(i.key)

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
        let it = SetIter()
        it.it2 = items.iter()
        return it


class SetIter:
    var it2: DictionaryIter[int] = DictionaryIter()

    fn next() -> Option[str]:
        return it2.next()
