
from utils import panic

pub enum Option[D]:
	Some(value?: D)
	None

pub fn option_unwrap[T](option?: Option[T]) -> T:
	case option:
		Some(value):
			value
		None:
			panic("Cannot unwrap None")

pub fn option_unwrap_or[T](option: Option[T], default: T) -> T:
	case option:
		Some(value):
			value
		None:
			default

pub fn option_is_some[T](opt?: Option[T]) -> bool:
	case opt:
		Some(v):
			true
		None:
			false

pub fn option_is_none[T](opt?: Option[T]) -> bool:
	case opt:
		Some(v):
			false
		None:
			true
