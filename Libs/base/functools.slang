
from listtype import List
from optiontype import option_unwrap
from utils import assert

pub fn zip[L,R,P](left: List[L], right: List[R], merger: fn(L, R) -> P) -> List[P]:
	# Zip two lists into a merged list!
	assert(condition: left.len() == right.len(), message: "Can only zip lists of equal length")

	let pairs: List[P] = List()
	let b_iter = right.iter()
	for a in left:
		let b = option_unwrap(b_iter.next())
		let pair = merger(a, b)
		pairs.append(pair)

	pairs

fn add_int(left: int, right: int) -> int:
	left + right

pub fn sum_integers(values: List[int]) -> int:
	reduce(values, f: add_int)

pub fn reduce[T](values: List[T], f: fn(T, T) -> T) -> T:
	# Apply a function on pairs to reduce to a single item.
	var res = values.pop_front()
	for other in values:
		res = f(res, other)
	res

pub fn map[T,V](values: List[T], function: fn(T) -> V) -> List[V]:
	let mapped: List[V] = List()
	for value in values:
		mapped.append(function(value))
	mapped

pub fn filter[T](values: List[T], criterium: fn(T) -> bool) -> List[T]:
	let allowed: List[T] = List()
	for value in values:
		if criterium(value):
			allowed.append(value)
	allowed

pub fn all[T](values: List[T], check: fn(T) -> bool) -> bool:
	for value in values:
		if not check(value):
			return false
	true

# fn pairs[L,R](left: List[L], right: List[R]) -> List[Pair[L, R]]:
#     zip(left, right, merger: make_pair)

# fn make_pair[L,R](left: L, right: R) -> Pair[L, R]:
#     Pair(left, right)

# struct Pair[L,R]:
#     left: L
#     right: R
