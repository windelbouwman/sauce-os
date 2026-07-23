module compiler.html
"""Module to create documentation from parsed code"""

from base.listtype import List
from base.vectype import Vector
from base.optiontype import option_is_some
from base.fs import Path
from base.logging import log_info
from base.strlib import str_join
from base.optiontype import option_unwrap, Option

from text_gen import TextGenerator
import ast
from string_table import StringTable

pub fn create_docs(strtab: StringTable, module_defs: List[ast.ModuleDef], output_filename: Option[Path]):
	log_info("Generating HTML")
	var out = TextGenerator()
	out.begin(output_filename)
	let g = HtmlGenerator(strtab, out)
	out.writeln("<!DOCTYPE html>")
	out.writeln("<html>")
	out.writeln("<head>")
	out.writeln("<link rel=\"stylesheet\" href=\"doc-style.css\" />")
	out.writeln("</head>")
	out.writeln("<body>")
	for module_def in module_defs:
		if option_is_some(module_def.filename):
			g.gen_module(module_def)
	out.writeln("</body>")
	out.writeln("</html>")
	out.end()

class HtmlGenerator:
	var strtab: StringTable
	var out: TextGenerator

	pub fn gen_module(module_def: ast.ModuleDef):
		enter_span("signature")
		gen_kw("module")
		text(" ")
		text(module_def.get_name(strtab))
		leave_span()
		gen_docstring(module_def.docstring)
		for definition in module_def.definitions:
			gen_definition(definition)

	fn gen_definition(definition: ast.Definition):
		enter_div()
		case definition:
			Function(function_def):
				case function_def.body:
					Intern(scoped_block):
						gen_function(function_def)
				else:
					pass
			Class(class_def):
				gen_class(class_def)
			Struct(struct_def):
				gen_struct(struct_def)
			Enum(enum_def):
				gen_enum(enum_def)
			Var(variable_def):
				gen_variable(variable_def)
		else:
			text(ast.definition_to_str(strtab, definition))
		leave_div()

	fn gen_struct(struct_def: ast.StructDef):
		gen_anchor(struct_def.id)
		enter_span("signature")
		if struct_def.is_pub:
			gen_kw("pub ")
		gen_kw("struct")
		text(" ")
		gen_id(struct_def.id)
		gen_type_parameters(struct_def.type_parameters)
		leave_span()
		gen_docstring(struct_def.docstring)
		enter_div()
		for field in struct_def.fields:
			enter_span("signature")
			gen_name(field.name)
			text(": ")
			gen_type(field.ty)
			leave_span()
		leave_div()

	fn gen_enum(enum_def: ast.EnumDef):
		gen_anchor(enum_def.id)
		enter_span("signature")
		if enum_def.is_pub:
			gen_kw("pub ")
		gen_kw("enum")
		text(" ")
		gen_name(enum_def.id.name)
		gen_type_parameters(enum_def.type_parameters)
		leave_span()
		gen_docstring(enum_def.docstring)
		enter_div()
		for variant in enum_def.variants:
			enter_span("signature")
			gen_name(variant.name)
			if not variant.payload.is_empty():
				text("(")
				var i = 0
				for item in variant.payload:
					gen_type(item)
					i += 1
					if i < variant.payload.len():
						text(", ")
				text(")")
			leave_span()
		leave_div()

	fn gen_class(class_def: ast.ClassDef):
		gen_anchor(class_def.id)
		enter_span("signature")
		if class_def.is_pub:
			gen_kw("pub ")
		gen_kw("class")
		text(" ")
		gen_id(class_def.id)
		gen_type_parameters(class_def.type_parameters)
		leave_span()
		gen_docstring(class_def.docstring)
		for definition in class_def.definitions:
			gen_definition(definition)

	fn gen_variable(variable_def: ast.VariableDef):
		enter_span("signature")
		if variable_def.is_pub:
			gen_kw("pub ")
		gen_kw("var")
		text(" ")
		gen_id(variable_def.variable.id)
		text(": ")
		gen_type(variable_def.variable.ty)
		leave_span()

	fn gen_function(function_def: ast.FunctionDef):
		enter_span("signature")
		if function_def.is_pub:
			gen_kw("pub ")
		gen_kw("fn")
		text(" ")
		gen_name(function_def.name)
		gen_type_parameters(function_def.type_parameters)
		text("(")
		var i = 0
		for parameter in function_def.parameters:
			gen_name(parameter.id.name)
			if parameter.label_is_optional:
				text("?")
			text(": ")
			gen_type(parameter.ty)
			i += 1
			if i < function_def.parameters.len():
				text(", ")
		text(")")
		if not function_def.info.return_type.is_void():
			text(" -> ")
			gen_type(function_def.info.return_type)
		if not function_def.info.except_type.is_void():
			text(" except ")
			gen_type(function_def.info.except_type)
		leave_span()
		gen_docstring(function_def.docstring)

	pub fn gen_docstring(docstring?: Option[ast.DocString]):
		enter_div()
		case docstring:
			Some(docstring):
				for line in docstring.lines:
					out.writeln("{line}<br />")
			None:
				pass
		leave_div()

	fn gen_type(ty?: ast.Type):
		if ty.is_int():
			let bits = ty.get_bits()
			spanned("int{bits}" if ty.is_signed_int() else "uint{bits}", cls: "identifier")
		elif ty.is_bool():
			spanned("bool", cls: "identifier")
		elif ty.is_str():
			spanned("str", cls: "identifier")
		elif ty.is_float():
			let bits = ty.get_bits()
			spanned("float{bits}", cls: "identifier")
		elif ty.is_char():
			spanned("char", cls: "identifier")
		elif ty.is_class():
			let class_def = ty.get_class_def()
			gen_id(class_def.id)
			gen_type_arguments(ty.get_type_arguments())
		elif ty.is_array():
			text("[")
			gen_type(ty.get_element_type())
			text("]")
		elif ty.is_struct():
			let struct_def = ty.get_struct_def()
			gen_id(struct_def.id)
		elif ty.is_enum():
			let enum_def = ty.get_enum_def()
			gen_id(enum_def.id)
		elif ty.is_function_type():
			gen_kw("fn")
			text(" (")
			let parameter_types = ty.get_parameter_types()
			var i = 0
			for param_ty in parameter_types:
				gen_type(param_ty.ty)
				i += 1
				if i < parameter_types.len():
					text(", ")
			text(")")
			let return_type = ty.get_return_type()
			if not return_type.is_void():
				text(" -> ")
				gen_type(return_type)
		elif ty.is_type_parameter():
			let type_parameter = ty.get_type_parameter()
			gen_id(type_parameter.id)
		else:
			text(ast.type_to_string(strtab, ty))

	fn gen_type_parameters(parameters?: List[ast.TypeParameter]):
		if parameters.is_empty():
			return
		text("[")
		var i = 0
		for parameter in parameters:
			gen_name(parameter.id.name)
			i += 1
			if i < parameters.len():
				text(",")
		text("]")

	fn gen_type_arguments(arguments?: Vector[ast.Type]):
		if arguments.is_empty():
			return
		text("[")
		var i = 0
		for ty in arguments:
			gen_type(ty)
			i += 1
			if i < arguments.len():
				text(",")
		text("]")

	fn gen_kw(kw?: str):
		spanned(kw, cls: "keyword")

	fn gen_anchor(id?: ast.NodeId):
		text("<a id=\"{id.id}\"></a>")

	fn gen_id(id?: ast.NodeId):
		text("<a href=\"#{id.id}\">")
		gen_name(id.name)
		text("</a>")

	fn gen_name(name?: uint32):
		spanned(strtab.get(name), cls: "identifier")

	fn text(t?: str):
		out.write(t)

	fn spanned(t?: str, cls: str):
		enter_span(cls)
		text(t)
		leave_span()

	fn enter_span(cls?: str):
		text("<span class=\"{cls}\">")

	fn leave_span():
		text("</span>")

	fn enter_div():
		out.writeln("<div class=\"itembox\">")

	fn leave_div():
		out.writeln("</div>")
