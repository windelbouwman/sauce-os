
# Functions to serialize type definitions to JSON.

from utils import unimplemented, panic
from utils import log_info, log_debug, log_trace
from datatypes import List, Option, option_is_some
from vectype import Vector, new_vector, new_vector_with_capacity
from hashmap import HashMap
from pathlib import basename
from json import JsonBuilder, JsonException, write_json_to_file, read_json_from_file
from json import JsonValue, JsonBrowser
from location import location_default
import ast

pub fn store_symbol_table(module_set: ast.ModuleSet, filename: str):
	# Save symbol table for later use.
	# This is useful when saving a symbol table
	# to file.
	# This is done when compiling a library. When using this library
	# we must reload types from this stored data.
	log_info("Saving type info to: {filename}")

	# TODO: we could use ast.Visitor here
	let libname = basename(path: filename)
	let saver = SymbolSaver(m_libname: libname)

	let obj = saver.save_modules(module_set)
	write_json_to_file(filename, obj)

class SymbolSaver:
	var m_ser: JsonBuilder = JsonBuilder()
	var m_libname: str

	pub fn save_modules(module_set: ast.ModuleSet) -> JsonValue:
		m_ser.begin_object()
		m_ser.add_text_attribute(attr: "compiler-version", text: "2024")
		m_ser.add_text_attribute(attr: "libname", text: m_libname)
		m_ser.begin_array()
		for module in module_set.modules:
			if option_is_some(module.filename):
				log_info("Saving meta-info for module: {module.name}")
				save_module(module)
			else:
				log_debug("Skip saving meta-info for module: {module.name}")
		m_ser.end_array_as_attribute(attr: "modules")
		m_ser.end_object()

	fn save_module(module: ast.Module):
		m_ser.begin_object()
		m_ser.add_text_attribute(attr: "name", text: module.name)
		m_ser.begin_array()
		for imp in module.imports:
			save_import(imp)
		m_ser.end_array_as_attribute(attr: "imports")
		m_ser.begin_array()
		for definition in module.definitions:
			save_definition(definition)
		m_ser.end_array_as_attribute(attr: "definitions")
		m_ser.end_object_as_element()
	
	fn save_import(imp: ast.Import):
		m_ser.begin_object()
		m_ser.add_text_attribute(attr: "modname", text: imp.modname)
		case imp.kind:
			Self:
				pass
			Names(names):
				m_ser.begin_array()
				for name in names:
					m_ser.add_text_as_element(text: name.name)
				m_ser.end_array_as_attribute(attr: "names")
		m_ser.end_object_as_element()

	fn save_definition(definition: ast.Definition):
		# Do not export, when not explicitly set to public.
		case definition:
			Function(function_def):
				if not function_def.is_pub:
					return
			# Struct(struct_def):
			#     if not struct_def.is_pub:
			#         return
			# Class(class_def):
			#     if not class_def.is_pub:
			#         return
			# Enum(enum_def):
			#     if not enum_def.is_pub:
			#         return
		else:
			pass

		log_debug("Saving {ast.definition_to_str(definition)}")
		m_ser.begin_object()
		case definition:
			Macro(macro_def):
				save_macro_def(macro_def)
			Function(function_def):
				save_function_def(function_def)
			Struct(struct_def):
				save_struct_def(struct_def)
			Class(class_def):
				save_class_def(class_def)
			Enum(enum_def):
				save_enum_def(enum_def)
			Var(variable_def):
				save_var_def(variable_def)
		m_ser.end_object_as_element()

	fn save_macro_def(macro_def: ast.MacroDef):
		unimplemented("macro-def")

	fn save_var_def(variable_def: ast.VariableDef):
		m_ser.add_text_attribute(attr: "kind", text: "variable")
		m_ser.add_boolean_attribute(attr: "pub", value: variable_def.is_pub)
		save_id(id: variable_def.variable.id)
		save_type(attr: "type", ty: variable_def.variable.ty)
		let is_initialized = false
		case variable_def.value:
			Intern(value):
				is_initialized = option_is_some(value)
			Extern(libname, initialized):
				is_initialized = initialized
		m_ser.add_boolean_attribute(attr: "initialized", value: is_initialized)

	fn save_enum_def(enum_def: ast.EnumDef):
		m_ser.add_text_attribute(attr: "kind", text: "enum")
		m_ser.add_boolean_attribute(attr: "pub", value: enum_def.is_pub)
		save_id(id: enum_def.id)
		save_type_parameters(type_parameters: enum_def.type_parameters)
		save_doc_string(docstring: enum_def.docstring)

		m_ser.begin_array()
		for variant in enum_def.variants:
			m_ser.begin_object()
			m_ser.add_text_attribute(attr: "name", text: variant.name)
			m_ser.begin_array()
			for payload in variant.payload:
				m_ser.begin_object()
				save_type(attr: "type", ty: payload)
				m_ser.end_object_as_element()
			m_ser.end_array_as_attribute(attr: "payload")
			m_ser.end_object_as_element()
		m_ser.end_array_as_attribute(attr: "variants")

	fn save_class_def(class_def: ast.ClassDef):
		m_ser.add_text_attribute(attr: "kind", text: "class")
		m_ser.add_boolean_attribute(attr: "pub", value: class_def.is_pub)
		save_id(id: class_def.id)
		save_type_parameters(type_parameters: class_def.type_parameters)
		save_doc_string(docstring: class_def.docstring)

		m_ser.begin_array()
		for definition in class_def.definitions:
			save_definition(definition)
		m_ser.end_array_as_attribute(attr: "definitions")

	fn save_function_def(function_def: ast.FunctionDef):
		m_ser.add_text_attribute(attr: "kind", text: "function")
		m_ser.add_boolean_attribute(attr: "pub", value: function_def.is_pub)
		m_ser.add_text_attribute(attr: "name", text: function_def.name)
		m_ser.add_integer_attribute(attr: "id", value: 0)
		save_type_parameters(type_parameters: function_def.type_parameters)
		save_doc_string(docstring: function_def.docstring)

		# Parameters
		m_ser.begin_array()
		for parameter_def in function_def.parameters:
			m_ser.begin_object()
			m_ser.add_text_attribute(attr: "name", text: parameter_def.id.name)
			m_ser.add_boolean_attribute(attr: "label_is_optional", value: parameter_def.label_is_optional)
			save_type(attr: "type", ty: parameter_def.ty)
			m_ser.end_object_as_element()
		m_ser.end_array_as_attribute(attr: "parameters")
		save_function_info(info: function_def.info)

	fn save_function_info(info: ast.FunctionInfo):
		save_type(attr: "return-type", ty: info.return_type)
		save_type(attr: "except-type", ty: info.except_type)

	fn save_struct_def(struct_def: ast.StructDef):
		log_debug("Saving meta-info for struct-def: {ast.node_id_to_string(struct_def.id)}")
		m_ser.add_text_attribute(attr: "kind", text: "struct")
		m_ser.add_boolean_attribute(attr: "pub", value: struct_def.is_pub)
		save_id(id: struct_def.id)
		save_type_parameters(type_parameters: struct_def.type_parameters)
		save_doc_string(docstring: struct_def.docstring)

		# Fields
		m_ser.begin_array()
		for field in struct_def.fields:
			m_ser.begin_object()
			m_ser.add_text_attribute(attr: "name", text: field.name)
			save_type(attr: "type", ty: field.ty)
			m_ser.end_object_as_element()
			
		m_ser.end_array_as_attribute(attr: "fields")

	fn save_doc_string(docstring: Option[str]):
		case docstring:
			Some(text):
				m_ser.add_text_attribute(attr: "docstring", text)
			None:
				pass

	fn save_type_parameters(type_parameters: List[ast.TypeParameter]):
		m_ser.begin_array()
		for type_parameter in type_parameters:
			m_ser.begin_object()
			save_id(id: type_parameter.id)
			m_ser.end_object_as_element()
		m_ser.end_array_as_attribute(attr: "type-parameters")

	fn save_type(attr: str, ty: ast.Type):
		m_ser.begin_object()
		if ty.is_int():
			m_ser.add_text_attribute(attr: "kind", text: "int")
			let signed = ty.is_signed_int()
			let bits = ty.get_bits()
			m_ser.add_boolean_attribute(attr: "signed", value: signed)
			m_ser.add_integer_attribute(attr: "bits", value: bits)
		elif ty.is_str():
			m_ser.add_text_attribute(attr: "kind", text: "str")
		elif ty.is_float():
			m_ser.add_text_attribute(attr: "kind", text: "float")
			let bits = ty.get_bits()
			m_ser.add_integer_attribute(attr: "bits", value: bits)
		elif ty.is_bool():
			m_ser.add_text_attribute(attr: "kind", text: "bool")
		elif ty.is_char():
			m_ser.add_text_attribute(attr: "kind", text: "char")
		elif ty.is_void():
			m_ser.add_text_attribute(attr: "kind", text: "void")
		elif ty.is_unreachable():
			m_ser.add_text_attribute(attr: "kind", text: "unreachable")
		elif ty.is_array():
			m_ser.add_text_attribute(attr: "kind", text: "array")
			let element_type = ty.get_element_type()
			save_type(attr: "element-type", ty: element_type)
			let size = ty.get_array_size()
			m_ser.add_integer_attribute(attr: "size", value: size)
		elif ty.is_type_parameter():
			m_ser.add_text_attribute(attr: "kind", text: "type-parameter")
			let type_parameter = ty.get_type_parameter()
			save_id(id: type_parameter.id)
		elif ty.is_tycon_app():
			m_ser.add_text_attribute(attr: "kind", text: "app")
			let tycon = ty.get_tycon()
			let type_arguments = ty.get_type_arguments()

			save_tycon(tycon)

			m_ser.begin_array()
			for type_argument in type_arguments:
				m_ser.begin_object()
				save_type(attr: "type", ty: type_argument)
				m_ser.end_object_as_element()
			m_ser.end_array_as_attribute(attr: "type-arguments")
		elif ty.is_function_type():
			m_ser.add_text_attribute(attr: "kind", text: "function")
			let parameter_types = ty.get_parameter_types()
			let return_type = ty.get_return_type()
			let except_type = ty.get_except_type()
			m_ser.begin_array()
			for parameter_type in parameter_types:
				m_ser.begin_object()
				save_type(attr: "type", ty: parameter_type.ty)
				m_ser.end_object_as_element()
			m_ser.end_array_as_attribute(attr: "parameter-types")
			m_ser.add_boolean_attribute(attr: "no-return", value: false) # TODO
			save_type(attr: "return-type", ty: return_type)
			save_type(attr: "except-type", ty: except_type)
		else:
			panic("save_type: Not-impl: {ty}")
		m_ser.end_object_as_attribute(attr)
	
	fn save_tycon(tycon: ast.TyCon):
		case tycon:
			Struct(struct_def):
				save_id(id: struct_def.id)
			Enum(enum_def):
				save_id(id: enum_def.id)
			Class(class_def):
				save_id(id: class_def.id)
			Ref(key):
				panic("Cannot save tycon ref")
			NameRef(key):
				panic("Cannot save tycon name-ref")

	fn save_id(id: ast.NodeId):
		m_ser.add_text_attribute(attr: "name", text: id.name)
		m_ser.add_integer_attribute(attr: "id", value: id.id)

pub fn load_symbol_table(filename: str) -> List[ast.Module]:
	log_info("Read type info from: {filename}")
	let loader = SymbolLoader()
	try:
		let obj = read_json_from_file(filename)
		loader.push_json(value: obj)
	except (oei : JsonException):
		panic("Invalid json at {oei.pos}: {oei.message}")

	loader.load_modules()

class SymbolLoader:
	var m_des: JsonBrowser = JsonBrowser()
	var m_type_parameter_map: HashMap[ast.NodeId,ast.TypeParameter] = ast.new_hashmap_nodeid()
	var m_this_type: Option[ast.Type] = Option.None()
	var m_libname: str = "?"

	pub fn push_json(value: JsonValue):
		m_des.push_value(value)
	
	pub fn load_modules() -> List[ast.Module]:
		let compiler_version_info = m_des.get_text_attribute(attr: "compiler-version")
		log_info("Compiler-info: {compiler_version_info}")
		m_libname = m_des.get_text_attribute(attr: "libname")

		let modules: List[ast.Module] = List()
		for module_obj in m_des.get_array_attribute(attr: "modules"):
			m_des.push_value(value: module_obj)
			let module = load_module()
			m_des.pop_value()
			modules.append(module)

		modules

	fn load_module() -> ast.Module:
		let mod_name = m_des.get_text_attribute(attr: "name")
		log_info("Load info for module: {mod_name}")

		let imports: Vector[ast.Import] = new_vector()
		for import_obj in m_des.get_array_attribute(attr: "imports"):
			m_des.push_value(value: import_obj)
			imports.append(load_import())
			m_des.pop_value()

		let definitions: List[ast.Definition] = List()
		for definition_obj in m_des.get_array_attribute(attr: "definitions"):
			m_des.push_value(value: definition_obj)
			definitions.append(load_definition())
			m_des.pop_value()
		ast.new_module(name: mod_name, filename: Option.None(), imports, definitions)
	
	fn load_import() -> ast.Import:
		let modname = m_des.get_text_attribute(attr: "modname")
		let location = location_default()
		if m_des.has_attribute(attr: "names"):
			let names: List[ast.NameAtLocation] = List()
			for name_obj in m_des.get_array_attribute(attr: "names"):
				m_des.push_value(value: name_obj)
				names.append(ast.NameAtLocation(name: m_des.get_text(), location))
				m_des.pop_value()
			let kind = ast.ImportKind.Names(names)
			ast.Import(modname, kind, location)
		else:
			let kind = ast.ImportKind.Self()
			ast.Import(modname, kind, location)

	fn load_definition() -> ast.Definition:
		let def_kind = m_des.get_text_attribute(attr: "kind")
		let def_name = m_des.get_text_attribute(attr: "name")
		let def_id = m_des.get_integer_attribute(attr: "id")
		log_trace("  --> DEF-{def_kind}: {def_name} / {def_id}")
		if def_kind == "function":
			let function_def = load_function(def_name, def_id)
			ast.Definition.Function(function_def)
		elif def_kind == "struct":
			let struct_def = load_struct_def(def_name, def_id)
			ast.Definition.Struct(struct_def)
		elif def_kind == "enum":
			let enum_def = load_enum_def(def_name, def_id)
			ast.Definition.Enum(enum_def)
		elif def_kind == "class":
			let class_def = load_class_def(def_name, def_id)
			ast.Definition.Class(class_def)
		elif def_kind == "variable":
			let variable_def = load_variable_def(def_name, def_id)
			ast.Definition.Var(variable_def)
		else:
			panic("Not implemented definition kind: {def_kind}")

	fn load_variable_def(def_name: str, def_id: int) -> ast.VariableDef:
		let is_pub = m_des.get_boolean_attribute(attr: "pub")
		let id = ast.NodeId(name: def_name, id: def_id)
		let ty = load_type(attr: "type")
		let location = location_default()
		let variable = ast.Variable(id, ty, location)
		let is_initialized = m_des.get_boolean_attribute(attr: "initialized")
		ast.VariableDef:
			is_pub
			variable
			value: ast.VariableDefValue.Extern(libname: m_libname, is_initialized)

	fn load_function(def_name: str, def_id: int) -> ast.FunctionDef:
		let is_pub = m_des.get_boolean_attribute(attr: "pub")
		let type_parameters = load_type_parameters()
		let docstring = load_docstring()
		let parameters = load_parameters()
		let info = load_function_info()
		let f = ast.extern_function_def:
			is_pub
			libname: m_libname
			name: def_name
			docstring
			type_parameters
			parameters
			return_type: info.return_type
			location: location_default()
		f.info = info
		case m_this_type:
			Some(ty):
				let this_parameter = ast.parameter_def(name: "this", id: 0, label_is_optional: true, ty, location: location_default())
				f.this_parameter = Option.Some(this_parameter)
			None:
				pass
		f

	fn load_function_info() -> ast.FunctionInfo:
		let return_type = load_type(attr: "return-type")
		let except_type = load_type(attr: "except-type")
		ast.FunctionInfo(return_type, except_type)

	fn load_parameters() -> List[ast.ParameterDef]:
		let parameters: List[ast.ParameterDef] = List()
		for parameter_obj in m_des.get_array_attribute(attr: "parameters"):
			m_des.push_value(value: parameter_obj)
			parameters.append(load_parameter())
			m_des.pop_value()
		parameters
	
	fn load_parameter() -> ast.ParameterDef:
		let name = m_des.get_text_attribute(attr: "name")
		let label_is_optional = m_des.get_boolean_attribute(attr: "label_is_optional")
		let id = 0
		let ty = load_type(attr: "type")
		let location = location_default()
		ast.parameter_def(name, id, label_is_optional, ty, location)

	fn load_struct_def(def_name: str, def_id: int) -> ast.StructDef:
		let builder = ast.StructBuilder()
		let is_pub = m_des.get_boolean_attribute(attr: "pub")
		builder.set_name(name: def_name)
		builder.set_id(id: def_id)
		builder.set_pub(is_pub)
		let type_parameters = load_type_parameters()
		let docstring = load_docstring()
		for field_obj in m_des.get_array_attribute(attr: "fields"):
			m_des.push_value(value: field_obj)
			let field_name = m_des.get_text_attribute(attr: "name")
			let field_type = load_type(attr: "type")
			builder.add_field(name: field_name, ty: field_type, location: location_default())
			m_des.pop_value()
		let struct_def = builder.finish()
		struct_def.type_parameters = type_parameters
		struct_def.docstring = docstring
		struct_def.scope = ast.Scope()
		struct_def
	
	fn load_enum_def(def_name: str, def_id: int) -> ast.EnumDef:
		let location = location_default()
		let is_pub = m_des.get_boolean_attribute(attr: "pub")
		let docstring = load_docstring()
		let type_parameters = load_type_parameters()
		let variants: List[ast.EnumVariant] = List()
		let tag_index = 0
		for variant_obj in m_des.get_array_attribute(attr: "variants"):
			m_des.push_value(value: variant_obj)
			let variant_name = m_des.get_text_attribute(attr: "name")
			let payload = load_types(attr: "payload")
			let variant = ast.EnumVariant(name: variant_name, tag_value: tag_index, location, payload)
			variants.append(variant)
			m_des.pop_value()
			tag_index += 1

		ast.enum_def(is_pub, name: def_name, id: def_id, docstring, location, type_parameters, variants)

	fn load_class_def(def_name: str, def_id: int) -> ast.ClassDef:
		let id = ast.NodeId(name: def_name, id: def_id)
		let location = location_default()
		let is_pub = m_des.get_boolean_attribute(attr: "pub")
		let docstring = load_docstring()
		let type_parameters = load_type_parameters()

		let this_type = ast.undefined_type()
		m_this_type = Option.Some(this_type)
		let definitions: List[ast.Definition] = List()
		for definition_obj in m_des.get_array_attribute(attr: "definitions"):
			m_des.push_value(value: definition_obj)
			let definition = load_definition()
			definitions.append(definition)
			m_des.pop_value()
		m_this_type = Option.None()

		let class_def = ast.ClassDef(is_pub, id, docstring, location, is_extern: Option.Some(m_libname), type_parameters, definitions, scope: ast.Scope())

		# Patch the this type:
		let type_arguments: Vector[ast.Type] = new_vector_with_capacity(capacity: type_parameters.len())
		for type_parameter in type_parameters:
			type_arguments.append(ast.type_parameter_ref(type_parameter))
		this_type.change_to(to_type: ast.apply_tycon(tycon: ast.TyCon.Class(class_def), type_arguments))

		class_def

	fn load_docstring() -> Option[str]:
		"""Load optional docstring"""
		if m_des.has_attribute(attr: "docstring"):
			let text = m_des.get_text_attribute(attr: "docstring")
			Option.Some(text)
		else:
			Option.None()

	fn load_type_parameters() -> List[ast.TypeParameter]:
		let type_parameters: List[ast.TypeParameter] = List()
		for type_parameter_obj in m_des.get_array_attribute(attr: "type-parameters"):
			m_des.push_value(value: type_parameter_obj)
			let id = load_id()
			let location = location_default()
			let type_parameter = ast.new_type_parameter(name: id.name, id: id.id, location)
			m_type_parameter_map.insert(key: id, value: type_parameter)
			type_parameters.append(type_parameter)
			m_des.pop_value()
		type_parameters

	fn load_types(attr: str) -> Vector[ast.Type]:
		let types: Vector[ast.Type] = new_vector()
		for type_argument_obj in m_des.get_array_attribute(attr):
			m_des.push_value(value: type_argument_obj)
			types.append(load_type(attr: "type"))
			m_des.pop_value()
		types

	fn load_type(attr: str) -> ast.Type:
		m_des.enter_attribute(attr)
		let type_name = m_des.get_text_attribute(attr: "kind")
		let ty = if type_name == "int":
			let signed = m_des.get_boolean_attribute(attr: "signed")
			let bits = m_des.get_integer_attribute(attr: "bits")
			ast.specific_int_type(signed, bits)
		elif type_name == "str":
			ast.str_type()
		elif type_name == "bool":
			ast.bool_type()
		elif type_name == "float":
			let bits = m_des.get_integer_attribute(attr: "bits")
			ast.specific_float_type(bits)
		elif type_name == "char":
			ast.char_type()
		elif type_name == "void":
			ast.void_type()
		elif type_name == "unreachable":
			ast.unreachable_type()
		elif type_name == "app":
			let type_arguments = load_types(attr: "type-arguments")
			let id = load_id()
			let tycon = ast.TyCon.Ref(key: id)
			ast.new_type(kind: ast.TypeKind.App(tycon, type_arguments))
		elif type_name == "type-parameter":
			let id = load_id()
			let type_parameter = m_type_parameter_map.get(key: id)
			ast.type_parameter_ref(type_parameter)
		elif type_name == "array":
			let element_type = load_type(attr: "element-type")
			let size = m_des.get_integer_attribute(attr: "size")
			ast.array_type(element_type, size)
		elif type_name == "function":
			let parameter_types: Vector[ast.ParameterType] = new_vector()
			for parameter_obj in m_des.get_array_attribute(attr: "parameter-types"):
				m_des.push_value(value: parameter_obj)
				let parameter_type = load_type(attr: "type")
				parameter_types.append(ast.ParameterType(label: Option.None(), ty: parameter_type))
				m_des.pop_value()
			let info = load_function_info()
			ast.function_type(parameter_types, info)
		else:
			panic("Unsupported: {type_name}")
		
		m_des.pop_value()
		ty
	
	fn load_id() -> ast.NodeId:
		let id = m_des.get_integer_attribute(attr: "id")
		let name = m_des.get_text_attribute(attr: "name")
		ast.NodeId(id, name)
