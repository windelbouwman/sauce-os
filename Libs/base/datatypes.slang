
from utils import panic

pub enum Option[D]:
    Some(value?: D)
    None

pub fn option_unwrap[T](option?: Option[T]) -> T:
    case option:
        Some(value):
            value
        None:
            panic("Cannot unwrap None")

pub fn option_unwrap_or[T](option: Option[T], default: T) -> T:
    case option:
        Some(value):
            value
        None:
            default

pub fn option_is_some[T](opt?: Option[T]) -> bool:
    case opt:
        Some(v):
            true
        None:
            false

pub fn option_is_none[T](opt?: Option[T]) -> bool:
    case opt:
        Some(v):
            false
        None:
            true

pub fn list1[T](v1?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec

pub fn list2[T](v1?: T, v2?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec.append(v2)
    vec

pub fn list3[T](v1?: T, v2?: T, v3?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec.append(v2)
    vec.append(v3)
    vec

pub fn list4[T](v1?: T, v2?: T, v3?: T, v4?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec.append(v2)
    vec.append(v3)
    vec.append(v4)
    vec

pub fn list5[T](v1?: T, v2?: T, v3?: T, v4?: T, v5?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec.append(v2)
    vec.append(v3)
    vec.append(v4)
    vec.append(v5)
    vec

pub fn list6[T](v1?: T, v2?: T, v3?: T, v4?: T, v5?: T, v6?: T) -> List[T]:
    let vec: List[T] = List()
    vec.append(v1)
    vec.append(v2)
    vec.append(v3)
    vec.append(v4)
    vec.append(v5)
    vec.append(v6)
    vec

pub class List[T]:
    # Linked list based on a linked list of elements with next pointers.

    var head_element: Option[ListElement[T]] = Option.None()
    var tail_element: Option[ListElement[T]] = Option.None()
    var length: int = 0

    fn append(val?: T):
        # Create new linked list element:
        let new_element: ListElement[T] = ListElement:
            next: Option.None()
            data: val
        
        # Adjust head and tail pointers
        case tail_element:
            None:
                head_element = Option.Some(new_element)
                tail_element = Option.Some(new_element)
            Some(element):
                element.next = Option.Some(new_element)
                tail_element = Option.Some(new_element)
        length += 1

    fn prepend(val?: T):
        # Prepend value in front of list
        let new_element: ListElement[T] = ListElement(next: head_element, data: val)

        # Adjust head and tail pointers
        head_element = Option.Some(new_element)
        case tail_element:
            None:
                tail_element = Option.Some(new_element)
        else:
            pass
        length += 1

    fn is_empty() -> bool:
        case head_element:
            None:
                true
        else:
            false

    fn len() -> int:
        # Retrieve length of the list
        length

    fn clear():
        while not is_empty():
            let dummy = pop_front()

    fn drop_front():
        # Drop first item from list
        let x = pop_front()

    fn pop_front() -> T:
        case head_element:
            None:
                panic("List.pop_front from empty list!")
            Some(element):
                length -= 1
                head_element = element.next
                case head_element:
                    None:
                        tail_element = Option.None()
                else:
                    pass
                return element.data

    fn iter() -> ListIter[T]:
        let it = ListIter()
        it.next_element = head_element
        it

    fn first() -> T:
        # Retrieve first element
        case head_element:
            None:
                panic("List.first on empty list!")
            Some(element):
                element.data

    fn drop_last():
        # Drop last item from list
        let x = pop_last()

    fn pop_last() -> T:
        # Pop last element of the list
        case head_element:
            None:
                panic("List.pop_last from empty list!")
            Some(element):
                length -= 1
                case element.next:
                    None:
                        # single item in list!
                        head_element = Option.None()
                        tail_element = Option.None()
                        return element.data
                    Some(next_element):
                        # More than 1 item in the list

                        loop:
                            case next_element.next:
                                None:
                                    # This is the last item!
                                    element.next = Option.None()
                                    tail_element = Option.Some(element)
                                    return next_element.data
                                Some(next_next_element):
                                    # Slide to next item
                                    element = next_element
                                    next_element = next_next_element
                        panic("pop_last: Should not get here.")

    fn last() -> T:
        # Retrieve last element
        case tail_element:
            None:
                panic("List.last on empty list!")
            Some(element):
                element.data
    
    fn get(index: int) -> T:
        # Retrieve value at index
        let element = get_element(index)
        element.data
    
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
                        
                        # Check if we delete the last item:
                        case element.next:
                            None:
                                tail_element = prev_element
                        else:
                            pass
                        
                        length -= 1

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
        result
    
    fn take_extend(other?: List[T]):
        while not other.is_empty():
            append(other.pop_front())

    fn extend2(other?: List[T]):
        for value in other:
            append(value)

struct ListElement[T]:
    next: Option[ListElement[T]]
    data: T

class ListIter[T]:
    var next_element: Option[ListElement[T]] = Option.None()

    fn next() -> Option[T]:
        let opt = next_element
        case opt:
            None:
                Option.None()
            Some(nxt_element):
                let x = Option.Some(nxt_element.data)
                next_element = nxt_element.next
                x
