
# Idea: implement a list type as a linked list.
import std

struct List[T]:
    head_element: Option[ListElement[T]]

enum Option[T]:
    Some(value: T)
    None

struct ListElement[T]:
    next: Option[ListElement[T]]
    data: T

struct ListIter[T]:
    next: Option[ListElement[T]]

fn list_new[T]() -> List[T]:
    let x = List[T]:
        head_element: Option[ListElement[T]].None()
    return x

fn list_append[T](this: List[T], value: T):
    let new_tail_element = ListElement[T]:
        next: Option[ListElement[T]].None()
        data: value
    
    case this.head_element:
        None:
            this.head_element = Option[ListElement[T]].Some(new_tail_element)
        Some(element):
            # let mabye_element = element.next
            loop:
                case element.next:
                    None:
                        break
                    Some(nxt_element):
                        element = nxt_element
            element.next = Option[ListElement[T]].Some(new_tail_element)

fn list_iter_new[T](this: List[T]) -> ListIter[T]:
    # " Create an iterator looping over a list "
    let i = ListIter[T]:
        next: this.head_element
    return i

fn list_iter_next[T](this: ListIter[T]) -> Option[T]:
    # " Retrieve next item "
    let x = this.next
    case x:
        None:
            return Option[T].None()
        Some(next):
            this.next = next.next
            return Option[T].Some(next.data)
    # TODO: below is a bug:
    return Option[T].None()

fn list_walk(x: List[Integer]):
    let i = 0
    let mabye_element = x.head_element
    loop:
        case mabye_element:
            None:
                break
            Some(element):
                std.print("Item[{i}]={element.data.value}")
                mabye_element = element.next
        i = i + 1

fn main():
    let x: List[Integer] = list_new()
    # TODO: the below could work?
    # let x = list_new()

    list_append(this: x, value: new_integer(13))
    list_append(this: x, value: new_integer(12))
    #list_append(x, new_integer(2001))

    std.print("Walk 1")
    list_walk(x)

    list_append(this: x, value: new_integer(88))
    list_append(this: x, value: new_integer(1337))
    std.print("Iter integers")
    let x_iter = list_iter_new(this: x)
    loop:
        let maybe_value2 = list_iter_next(this: x_iter)
        case maybe_value2:
            None:
                break
            Some(value):
                std.print("Iter value: {value.value}")

    # Nicer syntax would be:
    # let y = List[String]()
    # y.append(new_string("Bla"))
    let y: List[String] = list_new()
    list_append(this: y, value: new_string("Bla"))
    list_append(this: y, value: new_string("Fu"))
    list_append(this: y, value: new_string("Baz"))
    std.print("Walk strings")
    let y_iter = list_iter_new(this: y)
    loop:
        let maybe_value = list_iter_next(this: y_iter)
        case maybe_value:
            None:
                break
            Some(value):
                std.print("Iter value: " + value.value)


struct Integer:
    value: int

fn new_integer(value?: int) -> Integer:
    let i = Integer:
        value: value
    return i

struct String:
    value: str

fn new_string(value?: str) -> String:
    let i = String:
        value: value
    return i