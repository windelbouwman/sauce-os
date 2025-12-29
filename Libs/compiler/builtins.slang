
import ast
from listtype import List, list1, list2
from optiontype import Option
from location import location_default

pub fn get_rt_module(typectx: ast.TypeContext) -> ast.ModuleDef:
	let is_pub = true
	let libname = "slangrt"
	let docstring: Option[str] = Option.None()
	let modname = "rt"
	let module = ast.new_empty_module(name: modname, location: location_default())
	let type_parameters: List[ast.TypeParameter] = List()

	let int_to_str = ast.extern_function_def:
		is_pub
		libname
		name: "int_to_str"
		docstring
		type_parameters
		parameters: list1(ast.unlabeled_parameter(name: "x", ty: typectx.int_type()))
		return_type: typectx.str_type()
		location: location_default()
	module.define_function(function_def: int_to_str)

	let char_to_str = ast.extern_function_def:
		is_pub
		libname
		name: "char_to_str"
		docstring
		type_parameters
		parameters: list1(ast.unlabeled_parameter(name: "value", ty: typectx.char_type()))
		return_type: typectx.str_type()
		location: location_default()
	module.define_function(function_def: char_to_str)

	let str_concat = ast.extern_function_def:
		is_pub
		libname
		name: "str_concat"
		docstring
		type_parameters
		parameters: list2(ast.unlabeled_parameter(name: "a", ty: typectx.str_type()), ast.unlabeled_parameter(name: "b", ty: typectx.str_type()))
		return_type: typectx.str_type()
		location: location_default()
	module.define_function(function_def: str_concat)

	let str_compare = ast.extern_function_def:
		is_pub
		libname
		name: "str_compare"
		docstring
		type_parameters
		parameters: list2(ast.unlabeled_parameter(name: "a", ty: typectx.str_type()), ast.unlabeled_parameter(name: "b", ty: typectx.str_type()))
		return_type: typectx.bool_type()
		location: location_default()
	module.define_function(function_def: str_compare)

	let str_len = ast.extern_function_def:
		is_pub
		libname
		name: "str_len"
		docstring
		type_parameters
		parameters: list1(ast.labeled_parameter(name: "text", ty: typectx.str_type()))
		return_type: typectx.int_type()
		location: location_default()
	module.define_function(function_def: str_len)

	let str_get = ast.extern_function_def:
		is_pub
		libname
		name: "str_get"
		docstring
		type_parameters
		parameters: list2(ast.labeled_parameter(name: "text", ty: typectx.str_type()), ast.labeled_parameter(name: "index", ty: typectx.int_type()))
		return_type: typectx.char_type()
		location: location_default()
	module.define_function(function_def: str_get)

	let ctz = ast.extern_function_def:
		is_pub
		libname
		name: "ctz"
		docstring
		type_parameters
		parameters: list1(ast.unlabeled_parameter(name: "value", ty: typectx.int_type()))
		return_type: typectx.int_type()
		location: location_default()
	module.define_function(function_def: ctz)

	let clz = ast.extern_function_def:
		is_pub
		libname
		name: "clz"
		docstring
		type_parameters
		parameters: list1(ast.unlabeled_parameter(name: "value", ty: typectx.int_type()))
		return_type: typectx.int_type()
		location: location_default()
	module.define_function(function_def: clz)

	let popcnt = ast.extern_function_def:
		is_pub
		libname
		name: "popcnt"
		docstring
		type_parameters
		parameters: list1(ast.unlabeled_parameter(name: "value", ty: typectx.int_type()))
		return_type: typectx.int_type()
		location: location_default()
	module.define_function(function_def: popcnt)

	module
