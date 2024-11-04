
from datatypes import List

fn find_min_value[T](values: List[T], cmp: fn(T, T) -> bool) -> T:
    let sorted = sort_list(values, cmp)
    sorted.first()

fn find_max_value[T](values: List[T], cmp: fn(T, T) -> bool) -> T:
    let sorted = sort_list(values, cmp)
    sorted.last()

fn sort_list[T](x?: List[T], cmp: fn(T, T) -> bool) -> List[T]:
    # Return a sorted list
    # API/proxy function, choose implementation here.
    merge_sort(m: x, cmp)

# Merge sort, simple to implement.
# See: https://en.wikipedia.org/wiki/Merge_sort

fn merge_sort[T](m: List[T], cmp: fn(T, T) -> bool) -> List[T]:
    if m.len() <= 1:
        # If we have a list of 0 or 1 elements, consider it sorted.
        m
    else:
        # Split list into two halfs, sort the halfs, and merge them
        let left: List[T] = List()
        let right: List[T] = List()
        let index = 0
        let n: int = m.len() / 2
        for value in m:
            if index < n:
                left.append(value)
            else:
                right.append(value)
            index += 1

        left = merge_sort(m: left, cmp)
        right = merge_sort(m: right, cmp)
        merge_two(left, right, cmp)

fn merge_two[T](left: List[T], right: List[T], cmp: fn(T, T) -> bool) -> List[T]:
    let result: List[T] = List()
    while not left.is_empty() and not right.is_empty():
        if cmp(left.first(), right.first()):
            result.append(left.pop_front())
        else:
            result.append(right.pop_front())

    while not left.is_empty():
        result.append(left.pop_front())
    while not right.is_empty():
        result.append(right.pop_front())
    result
