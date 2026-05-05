module compiler.string_table

from base.vectype import Vector, new_vector
from base.hashmap import HashMap, new_hashmap_str

pub class StringTable:
	"""String table used for string interning"""
	var m_table: Vector[str] = new_vector()
	var m_map: HashMap[str,uint32] = new_hashmap_str()

	pub fn intern(name?: str) -> uint32:
		"""Perform string interning on identifier"""
		if m_map.contains(key: name):
			m_map.get(key: name)
		else:
			let n = uint32(m_table.len())
			m_map.insert(key: name, value: n)
			m_table.append(name)
			n

	pub fn get(index?: uint32) -> str:
		m_table.get(index: int(index))
