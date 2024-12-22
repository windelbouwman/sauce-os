""" Binary heap implementation.

A binary heap is an implementation for a priority queue.

"""

from utils import panic

pub fn new_int_min_queue() -> PriorityQueue[int]:
    new_priority_queue_with_capacity(capacity: 10000, f: cmp_int_item)

fn cmp_int_item(a?: int, b?: int) -> bool:
    a < b

# fn new_min_queue[T]() -> MinQueue[T]:
#     let m_priority_queue: PriorityQueue[ItemWithCost[T]] = new_priority_queue_with_capacity(capacity: 100, f: cmp_item_with_cost)
#     MinQueue(m_priority_queue)

# fn cmp_item_with_cost[T](a?: ItemWithCost[T], b?: ItemWithCost[T]) -> bool:
#     a.cost < b.cost

# class MinQueue[T]:
#     var m_priority_queue: PriorityQueue[ItemWithCost[T]]

#     fn push(item?: T, cost: int):
#         m_priority_queue.push(ItemWithCost(cost, item))

#     fn pop() -> T:
#         m_priority_queue.pop().item

# struct ItemWithCost[T]:
#     cost: int
#     item: T

pub fn new_priority_queue_with_capacity[T](capacity: int, f: fn (T, T) -> bool) -> PriorityQueue[T]:
    let m_size = 0
    let m_items = [capacity : T]
    let hack = Hack(f: f)
    PriorityQueue(m_items, m_size, m_capacity: capacity, hack)

struct Hack[T]:
    f: fn(T, T) -> bool

pub class PriorityQueue[T]:
    var m_items: [T]
    var m_size: int
    var m_capacity: int
    var hack: Hack[T]

    fn push(item?: T):
        if m_size < m_capacity:
            m_items[m_size] = item
            m_size += 1
            sift_up(m_size - 1)
        else:
            panic("Push into full PriorityQueue")

    fn pop() -> T:
        if m_size > 0:
            let item = m_items[0]
            swap(0, m_size - 1)
            m_size -= 1
            sift_down(0)
            item
        else:
            panic("Pop from empty PriorityQueue")

    fn sift_down(index?: int):
        loop:
            let left = index * 2 + 1
            let right = left + 1

            # No child nodes:
            let j = if left < m_size:
                if right < m_size:
                    if compare(left, right):
                        left
                    else:
                        right
                else:
                    left
            else:
                break
            
            if compare(index, j):
                break
            else:
                swap(j, index)
                index = j
            
    fn sift_up(index?: int):
        while index > 0:
            let parent_index = (index - 1) / 2
            if compare(parent_index, index):
                return
            else:
                swap(parent_index, index)
                index = parent_index
    
    fn is_empty() -> bool:
        m_size == 0

    fn len() -> int:
        m_size

    fn get(index?: int) -> T:
        if index < m_size:
            m_items[index]
        else:
            panic("Index {index} out of range")

    fn compare(index1?: int, index2?: int) -> bool:
        let a = get(index1)
        let b = get(index2)
        this.hack.f(a, b)

    fn swap(a?: int, b?: int):
        let tmp = m_items[a]
        m_items[a] = m_items[b]
        m_items[b] = tmp
