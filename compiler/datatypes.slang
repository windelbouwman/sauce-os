
enum Option[D]:
    Some(D)
    None

enum Result[O,E]:
    Ok(O)
    Error(E)

# Boxed versions of int and str..
# TODO: figure out nicer way to store int and str in List
struct Integer:
    value: int

fn new_integer(value: int) -> Integer:
    let i = Integer:
        value: value
    return i

struct String:
    value: str

fn new_string(value: str) -> String:
    let i = String:
        value: value
    return i

class List[T]:
    # Linked list based on a linked list of elements with next pointers.

    var head_element: Option[ListElement[T]] = Option.None()

    fn append(val: T):
        let new_tail_element = ListElement:
            next: Option.None()
            data: val

        case this.head_element:
            None:
                this.head_element = Option.Some(new_tail_element)
            Some(element):
                loop:
                    case element.next:
                        None:
                            break
                        Some(nxt_element):
                            element = nxt_element
                element.next = Option.Some(new_tail_element)

    fn prepend(val: T):
        # Prepend value in front of list
        let new_head_element = ListElement:
            next: this.head_element
            data: val
        this.head_element = Option.Some(new_head_element)

    fn is_empty() -> bool:
        case this.head_element:
            None:
                return true
        else:
            return false

    fn len() -> int:
        # Retrieve length of the list
        case this.head_element:
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

    fn pop_front() -> T:
        case this.head_element:
            None:
                pass
                # Panic!
            Some(element):
                this.head_element = element.next
                return element.data

    fn iter() -> ListIter:
        let it = ListIter()
        it.next_element = this.head_element
        return it

    fn first() -> T:
        # Retrieve last element
        # TODO!
        pass

    fn pop_last() -> T:
        # Pop last element of the list
        # TODO!
        case this.head_element:
            None:
                # TODO: ERROR: empty list!
                pass
            Some(element):
                case element.next:
                    None:
                        # single item in list!
                        this.head_element = Option.None()
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

    fn last() -> T:
        # Retrieve last element
        # TODO!
        case this.head_element:
            None:
                # TODO: raise massive error?
                pass
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
        let n = 0

        case this.head_element:
            None:
                # TODO: raise massive error?
                pass
            Some(element):
                loop:
                    if n == index:
                        return element.data

                    case element.next:
                        None:
                            break
                        Some(nxt_element2):
                            element = nxt_element2
                    n = n + 1
                # TODO: raise massive error


struct ListElement[T]:
    next: Option[ListElement[T]]
    data: T

class ListIter[T]:
    var next_element: Option[ListElement[T]] = Option.None()

    fn next() -> Option[T]:
        let opt = this.next_element
        case opt:
            None:
                return Option.None()
            Some(nxt_element):
                let x = Option.Some(nxt_element.data)
                this.next_element = nxt_element.next
                return x
        # return Option.None()
