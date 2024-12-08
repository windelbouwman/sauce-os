
pub fn main() -> int:
    let dummy = List()
    0

class List[T]:
    var header: Option[ListItem[T]] = Option.None()

    fn append(value: T):
        let new_item = Option.Some(ListItem(data: value, next: Option.None()))

        case this.header:
            None:
                this.header = new_item
            Some(item):
                # while item.next
                
                loop:
                    case item.next:
                        None:
                            break
                        Some(next_item):
                            item = next_item
                item.next = new_item

struct ListItem[V]:
    data: V
    next: Option[ListItem[V]]

pub fn is_none[T](option: Option[T]) -> bool:
    case option:
        Some(value):
            true
        None:
            false

enum Option[D]:
    Some(value: D)
    None
