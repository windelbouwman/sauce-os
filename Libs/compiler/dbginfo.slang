
from listtype import List
from vectype import Vector, new_vector
from hashmap import HashMap, new_hashmap_str
from location import Location

pub class DbgInfo:
	pub var sources: List[Source] = List()
	var sources_by_filename: HashMap[str,Source] = new_hashmap_str()
	pub var functions: Vector[Function] = new_vector()
	var functions_by_name: HashMap[str,Function] = new_hashmap_str()

	pub fn add_source(filename: str, code: str):
		let source = Source(filename, code)
		sources.append(source)
		sources_by_filename.insert(key: filename, value: Source(filename, code))

	fn get_source(filename: str) -> Source:
		sources_by_filename.get(key: filename)

	pub fn add_function(name: str, filename: str, location: Location):
		let source = get_source(filename)
		let f = Function(name, location, source, start_label: "", end_label: "")
		functions.append(f)
		functions_by_name.insert(key: name, value: f)

	pub fn has_function(name: str) -> bool:
		functions_by_name.contains(key: name)

	pub fn get_function_by_name(name: str) -> Function:
		functions_by_name.get(key: name)

pub struct Source:
	filename: str
	code: str

pub struct Function:
	name: str
	location: Location
	source: Source
	start_label: str
	end_label: str
