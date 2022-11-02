
# Implement list with object oriented classes
# Idea: implement a list type as a linked list.

import std

class List:
    var head_element: Option = Option::None()

    fn append(val: int):
        let new_tail_element = ListElement:
            next: Option::None()
            data: val
        
        case this.head_element:
            Option::None:
                this.head_element = Option::Some(new_tail_element)
            Option::Some(element):
                let mabye_element = element.next
                loop:
                    case element.next:
                        Option::None:
                            break
                        Option::Some(nxt_element):
                            element = nxt_element
                element.next = Option::Some(new_tail_element)

    fn walk():
        let i = 0
        let mabye_element = this.head_element
        loop:
            case mabye_element:
                Option::None:
                    break
                Option::Some(element):
                    std::print("Item[" + std::int_to_str(i) + "]=" + std::int_to_str(element.data))
                    mabye_element = element.next
            i = i + 1

    fn iter() -> ListIter:
        let it = ListIter()
        it.next_element = this.head_element
        return it

# TODO: replace by Option<ListElement>
enum Option:
    Some(ListElement)
    None

struct ListElement:
    next: Option
    data: int

class ListIter:
    var next_element: Option = Option::None()

    fn next() -> Option:
        let opt = this.next_element
        case opt:
            Option::None:
                pass
            Option::Some(nxt_element):
                this.next_element = nxt_element.next
        return opt


fn main():
    let x = List()

    std::print("Walk 1")
    x.walk()

    x.append(13)
    x.append(12)
    x.append(2001)
    std::print("Walk 2")
    x.walk()

    x.append(88)
    std::print("Walk 3")
    x.walk()

    std::print("Iteration attempt")
    let it = x.iter()
    let n = 0
    loop:
        let opt = it.next()
        case opt:
            Option::None:
                break
            Option::Some(element):
                std::print("Item[" + std::int_to_str(n) + "]=" + std::int_to_str(element.data))
