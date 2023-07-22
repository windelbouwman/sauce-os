
# Idea: implement a list type as a linked list.
import std

struct List:
    head_element: Option

# TODO: replace by Option<ListElement>
enum Option:
    Some(value: ListElement)
    None

struct ListElement:
    next: Option
    data: int

struct ListIter:
    next_element: Option

fn list_iter_next(iter: ListIter) -> Option:
    let opt = iter.next_element
    case opt:
        None:
            pass
        Some(nxt_element):
            iter.next_element = nxt_element.next
    return opt

fn list_iter_new(x: List) -> ListIter:
    let i = ListIter:
        next_element: x.head_element
    return i

fn list_append(this: List, val: int):
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

fn list_walk(x: List):
    let i = 0
    let mabye_element = x.head_element
    loop:
        case mabye_element:
            None:
                break
            Some(element):
                std.print("Item[" + std.int_to_str(i) + "]=" + std.int_to_str(element.data))
                mabye_element = element.next
        i = i + 1

fn main():
    let x = list_new()

    std.print("Walk 1")
    list_walk(x)

    list_append(this: x, val: 13)
    list_append(this: x, val: 12)
    list_append(this: x, val: 2001)
    std.print("Walk 2")
    list_walk(x)

    list_append(this: x, val: 88)
    std.print("Walk 3")
    list_walk(x)

    std.print("Iteration attempt")
    let it = list_iter_new(x)
    let n = 0
    loop:
        let opt = list_iter_next(iter: it)
        case opt:
            None:
                break
            Some(element):
                std.print("Item[" + std.int_to_str(n) + "]=" + std.int_to_str(element.data))


fn list_new() -> List:
    let x = List:
        head_element: Option.None()
    return x
