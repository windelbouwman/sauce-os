from optiontype import Option
from utils import panic
from hashmap import HashMap, new_hashmap_str
# from strlib import int_to_hex_string
from bytes import ByteArray, Bytes

pub struct Section:
	data: Bytes

pub class BinaryOutput:
	var sections: HashMap[str, ByteArray] = new_hashmap_str()
	var current_section: Option[str] = Option.None()

	pub fn select_section(name: str):
		if not sections.contains(key: name):
			sections.insert(key: name, value: ByteArray())
		current_section = Option.Some(name)

	fn get_current_section() -> ByteArray:
		case current_section:
			Some(name):
				sections.get(key: name)
			None:
				panic("No output section selected")

	pub fn write_byte(value?: int):
		let b = get_current_section()
		b.append(value)

	pub fn write_bytes(data: Bytes):
		let b = get_current_section()
		b.extend(data)

	pub fn get_section_data(name: str) -> Bytes:
		sections.get(key: name).to_bytes()
