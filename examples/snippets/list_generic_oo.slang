
# Implement list with object oriented classes
# Idea: implement a list type as a linked list.

from std import print

struct Integer:
    value: int

fn new_integer(value?: int) -> Integer:
    Integer:
        value: value

class List[T]:
    var head_element: Option[ListElement[T]] = Option.None()

    pub fn append(val?: T):
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

    pub fn iter() -> ListIter[T]:
        let it = ListIter()
        it.next_element = this.head_element
        it

enum Option[D]:
    Some(value: D)
    None

struct ListElement[T]:
    next: Option[ListElement[T]]
    data: T

class ListIter[T]:
    pub var next_element: Option[ListElement[T]] = Option.None()

    pub fn next() -> Option[T]:
        let opt = this.next_element
        case opt:
            None:
                Option.None()
            Some(nxt_element):
                let x = Option.Some(nxt_element.data)
                this.next_element = nxt_element.next
                x

pub fn main() -> int:
    let x: List[Integer] = List()
    # Hmm, below does not infer that well..
    # let x = List()

    x.append(new_integer(13))
    x.append(new_integer(12))
    x.append(new_integer(2001))
    x.append(new_integer(88))

    print("Iteration attempt")
    let it = x.iter()
    let n = 0
    loop:
        let opt = it.next()
        case opt:
            None:
                break
            Some(element):
                print("Item[{n}]={element.value}")
        n = n + 1

    # This works when x has an 'iter' method:
    for e in x:
        print("Item[{n}]= {e.value}")
        n = n + 1
    
    0
