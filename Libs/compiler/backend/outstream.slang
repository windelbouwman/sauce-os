from optiontype import Option
from utils import panic
from hashmap import HashMap, new_hashmap_str
# from strlib import int_to_hex_string
from bytes import ByteArray, Bytes

pub struct Section:
	name: str
	data: ByteArray
	symbols: HashMap[str, int]

pub class BinaryOutput:
	var sections: HashMap[str, Section] = new_hashmap_str()
	var current_section: Option[str] = Option.None()

	pub fn select_section(name: str):
		if not sections.contains(key: name):
			let new_section = Section:
				name
				data: ByteArray()
				symbols: new_hashmap_str()
			sections.insert(key: name, value: new_section)
		current_section = Option.Some(name)

	fn get_current_section() -> Section:
		case current_section:
			Some(name):
				sections.get(key: name)
			None:
				panic("No output section selected")

	pub fn export_symbol(name?: str):
		let section = get_current_section()
		if section.symbols.contains(key: name):
			panic("Duplicate symbol: {name}")
		else:
			let offset = section.data.len()
			section.symbols.insert(key: name, value: offset)

	pub fn write_byte(value?: int):
		let section = get_current_section()
		section.data.append(value)

	pub fn write_bytes(data: Bytes):
		let section = get_current_section()
		section.data.extend(data)

	pub fn get_section(name: str) -> Section:
		sections.get(key: name)
