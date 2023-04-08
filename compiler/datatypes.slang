
enum<D> Option:
    Some(D)
    None


class<T> List:
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

    fn iter() -> ListIter:
        let it = ListIter()
        it.next_element = this.head_element
        return it

    fn first() -> T:
        # Retrieve last element
        # TODO!
        pass

    fn last() -> T:
        # Retrieve last element
        # TODO!
        # let element = this.head_element
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


struct<T> ListElement:
    next: Option[ListElement[T]]
    data: T

class<T> ListIter:
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
