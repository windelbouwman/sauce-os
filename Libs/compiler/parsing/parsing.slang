""" Recursive descent slang-lang parser.
"""
import ast
import std
from lexer import Lexer
from token import token_to_string, Token, default_token
from location import Location
from listtype import List, list1
from optiontype import Option
from vectype import Vector, new_vector
from pathlib import basename
from basepass import IdGen
from utils import log_debug, log_trace
from errors import CompilationError
import errors

pub fn parse_source(filename: str, id_gen: IdGen) -> ast.Module except CompilationError:
	let source = std.read_file(filename)
	let modname = basename(path: filename)
	let parser = Parser(id_gen)
	parser.feed(source)
	parser.parse_module(filename, name: modname)

pub fn parse_statement_from_text(source: str, id_gen: IdGen) -> ast.Statement except CompilationError:
	# Invoke parsing, purely on statement.
	let parser = Parser(id_gen)
	parser.feed(source)
	parser.parse_statement()

pub fn parse_expr_from_text(source: str, id_gen: IdGen) -> ast.Expression except CompilationError:
	# Invoke parsing, purely on expression.
	let parser = Parser(id_gen)
	parser.feed(source)
	parser.parse_expression()

class Parser:
	# An attempt at a recursive descent parser.
	var lex: Lexer = Lexer()
	var m_peek: Token = default_token()
	var m_peek2: Token = default_token()
	var filename: Option[str] = Option.None()
	var id_gen: IdGen
	var modname: Option[str] = Option.None()

	pub fn feed(source: str):
		lex.init(source)
		m_peek = lex.next_token()
		m_peek2 = lex.next_token()

	pub fn parse_module(filename: str, name: str) -> ast.Module except CompilationError:
		this.filename = Option.Some(filename)
		this.modname = Option.Some(name)
		let docstring = parse_optional_docstring()

		let imports: Vector[ast.Import] = new_vector()
		loop:
			case m_peek.kind:
				KwImport:
					move_token()
					imports.append(parse_import())
				KwFrom:
					move_token()
					imports.append(parse_from_import())
			else:
				break

		let definitions: List[ast.Definition] = List()
		loop:
			var tok = get_token()
			var is_pub = false
			case tok.kind:
				KwPub:
					is_pub = true
					tok = get_token()
				Eof:
					# We are done!
					break
			else:
				pass

			case tok.kind:
				KwMacro:
					let macro_def = parse_macro_def()
					definitions.append(ast.Definition.Macro(macro_def))
				KwFn:
					let func_def = parse_func_def(is_pub, this_parameter: Option.None())
					definitions.append(ast.Definition.Function(func_def))
				KwExtern:
					let libname = parse_raw_string()

					tok = get_token()
					case tok.kind:
						KwFn:
							let func_def = parse_extern_func_def(libname)
							definitions.append(ast.Definition.Function(func_def))
					else:
						raise unexpected_token(tok, expected: "'fn'")
				KwEnum:
					let enum_def = parse_enum_def(is_pub)
					definitions.append(ast.Definition.Enum(enum_def))
				KwStruct:
					let struct_def = parse_struct_def(is_pub)
					definitions.append(ast.Definition.Struct(struct_def))
				KwClass:
					let class_def = parse_class_def(is_pub)
					definitions.append(ast.Definition.Class(class_def))
				KwInterface:
					let interface_def = parse_interface_def(is_pub)
					definitions.append(ast.Definition.Interface(interface_def))
				KwImpl:
					let impl_def = parse_impl_def(location: tok.location)
					definitions.append(ast.Definition.Impl(impl_def))
				KwVar:
					let var_def = parse_var_def(is_pub)
					definitions.append(ast.Definition.Var(var_def))
			else:
				raise unexpected_token(tok, expected: "import, fn, enum, struct, class, extern")

		ast.new_module(name, filename: this.filename, imports, definitions)

	fn parse_import() -> ast.Import except CompilationError:
		let modname = parse_name()
		parse_newline()
		ast.import_self(modname: modname.name, location: modname.location)

	fn parse_from_import() -> ast.Import except CompilationError:
		let modname = parse_name()

		# 'import'
		let tok = get_token()
		case tok.kind:
			KwImport:
				pass
		else:
			raise unexpected_token(tok, expected: "'import'")

		let names: List[ast.NameAtLocation] = List()

		# list of names until newline:
		loop:
			names.append(parse_name())
			let tok2 = get_token()
			case tok2.kind:
				Comma:
					continue
				NewLine:
					break
			else:
				raise unexpected_token(tok: tok2, expected: "',' or newline")

		ast.import_names(modname: modname.name, location: modname.location, names)

	fn parse_macro_def() -> ast.MacroDef except CompilationError:
		# unimplemented("macro-def")
		let name_at = parse_name()

		parse_colon()
		parse_newline()
		parse_indent()
		let statement = parse_statement()
		parse_dedent()

		ast.MacroDef(name: name_at.name, location: name_at.location)

	fn parse_enum_def(is_pub: bool) -> ast.EnumDef except CompilationError:
		let name_at = parse_name()
		let type_parameters: List[ast.TypeParameter] = parse_type_parameters()

		parse_colon()
		parse_newline()
		parse_indent()
		let docstring = parse_optional_docstring()

		let variants: List[ast.EnumVariant] = List()
		var tag_index = 0
		while not try_parse_dedent():
			let variant_name_at = parse_name()
			let payload_types: Vector[ast.Type] = new_vector()
			case m_peek.kind:
				ParenthesisOpen:
					move_token()
					loop:
						payload_types.append(parse_parameter_def().ty)

						let tok4 = get_token()
						case tok4.kind:
							ParenthesisClose:
								break
							Comma:
								continue
						else:
							raise unexpected_token(tok: tok4, expected: "',' or ')'")
			else:
				pass

			let variant = ast.EnumVariant:
				name: variant_name_at.name
				tag_value: tag_index
				payload: payload_types
				location: variant_name_at.location
			variants.append(variant)
			tag_index += 1

			parse_newline()

		ast.enum_def(is_pub, name: name_at.name, id: new_id(), docstring, location: name_at.location, type_parameters, variants)

	fn parse_type_parameters() -> List[ast.TypeParameter] except CompilationError:
		let type_parameters: List[ast.TypeParameter] = List()
		case m_peek.kind:
			BracketOpen:
				move_token()
				# take in type parameters
				loop:
					let name_at = parse_name()
					type_parameters.append(ast.new_type_parameter(name: name_at.name, id: new_id(), location: name_at.location))

					let tok2 = get_token()
					case tok2.kind:
						BracketClose:
							break
						Comma:
							continue
					else:
						raise unexpected_token(tok: tok2, expected: "',' or ']'")
		else:
			pass
		type_parameters

	fn parse_struct_def(is_pub: bool) -> ast.StructDef except CompilationError:
		let name_at = parse_name()
		let type_parameters: List[ast.TypeParameter] = parse_type_parameters()
		parse_colon()
		parse_newline()
		parse_indent()
		let docstring = parse_optional_docstring()

		let fields: List[ast.StructField] = List()
		while not try_parse_dedent():
			let field_name_at = parse_name()
			parse_colon()
			let ty = parse_type()
			parse_newline()
			fields.append(ast.StructField(name: field_name_at.name, ty, location: field_name_at.location))

		ast.struct_def(is_pub, name: name_at.name, id: new_id(), docstring, type_parameters, fields, location: name_at.location)

	fn parse_class_def(is_pub: bool) -> ast.ClassDef except CompilationError:
		""" Parse a class definition. """
		let name_at = parse_name()
		log_debug("Parsing class: {name_at.name}")
		let type_parameters: List[ast.TypeParameter] = parse_type_parameters()
		parse_colon()
		parse_newline()
		parse_indent()
		let docstring = parse_optional_docstring()

		let definitions: List[ast.Definition] = List()
		# TODO: create type instance per 'this' parameter
		let this_type = ast.undefined_type()
		loop:
			# expect var/fn def or dedent (eventually)
			var is_pub2 = false
			var tok = get_token()
			case tok.kind:
				KwPub:
					is_pub2 = true
					tok = get_token()
				Dedent:
					break
			else:
				pass

			case tok.kind:
				KwVar:
					let var_def = parse_var_def(is_pub: is_pub2)
					definitions.append(ast.Definition.Var(var_def))
				KwFn:
					let this_parameter = ast.parameter_def(name: "this", id: new_id(), label_is_optional: true, ty: this_type, location: tok.location)
					let func_def = parse_func_def(is_pub: is_pub2, this_parameter: Option.Some(this_parameter))
					definitions.append(ast.Definition.Function(func_def))
			else:
				raise unexpected_token(tok, expected: "'var' or 'fn'")

		let class_def = ast.ClassDef:
			is_pub
			id: ast.NodeId(name: name_at.name, id: new_id())
			docstring
			location: name_at.location
			is_extern: Option.None()
			type_parameters
			definitions
			scope: ast.Scope()

		class_def.scope.class_scope = true

		# Prepare 'this' parameter:
		let type_arguments: Vector[ast.Type] = new_vector()
		for type_parameter in type_parameters:
			type_arguments.append(ast.type_parameter_ref(type_parameter))
		this_type.change_to(to_type: ast.apply_tycon(tycon: ast.TyCon.Class(class_def), type_arguments))
		class_def

	fn parse_interface_def(is_pub: bool) -> ast.InterfaceDef except CompilationError:
		""" Parse an interface definition. """
		let name_at = parse_name()
		log_debug("Parsing interface: {name_at.name}")
		let type_parameters: List[ast.TypeParameter] = parse_type_parameters()
		parse_colon()
		parse_newline()
		parse_indent()
		let docstring = parse_optional_docstring()

		let this_type = ast.opaque_type()
		let definitions: List[ast.Definition] = List()
		loop:
			let tok = get_token()

			case tok.kind:
				Dedent:
					break
				KwFn:
					let this_parameter = ast.parameter_def(name: "this", id: new_id(), label_is_optional: true, ty: this_type, location: tok.location)
					let func_def = parse_func_decl_def(this_parameter: Option.Some(this_parameter))
					definitions.append(ast.Definition.Function(func_def))
			else:
				raise unexpected_token(tok, expected: "'fn' or dedent")

		ast.InterfaceDef:
			is_pub
			id: ast.NodeId(name: name_at.name, id: new_id())
			type_parameters
			docstring
			location: name_at.location
			is_extern: Option.None()
			definitions
			scope: ast.Scope()

	fn parse_impl_def(location: Location) -> ast.ImplDef except CompilationError:
		log_debug("Parsing interface implementation")
		let interface_type = parse_type()
		parse_kw_for()
		let target_type = parse_type()
		parse_colon()
		parse_newline()
		parse_indent()
		let docstring = parse_optional_docstring()

		let this_type = target_type
		let definitions: List[ast.Definition] = List()
		loop:
			let tok = get_token()

			case tok.kind:
				Dedent:
					break
				KwFn:
					let this_parameter = ast.parameter_def(name: "this", id: new_id(), label_is_optional: true, ty: this_type, location: tok.location)
					let func_def = parse_func_def(is_pub: true, this_parameter: Option.Some(this_parameter))
					definitions.append(ast.Definition.Function(func_def))
			else:
				raise unexpected_token(tok, expected: "'fn' or dedent")

		let id = new_id()
		ast.ImplDef:
			id: ast.NodeId(name: "impl_{id}", id)
			interface_type
			target_type
			docstring
			location
			definitions
			scope: ast.Scope()

	fn parse_func_def(is_pub: bool, this_parameter: Option[ast.ParameterDef]) -> ast.FunctionDef except CompilationError:
		let name_at = parse_name()
		log_debug("Parsing function: {name_at.name}")
		let type_parameters = parse_type_parameters()
		let parameters = parse_parameters()
		let info = parse_function_info()

		# Body
		parse_colon()
		parse_newline()
		parse_indent()
		let docstring = parse_optional_docstring()

		let inner: Vector[ast.Statement] = new_vector()
		while not try_parse_dedent():
			let statement = parse_statement()
			inner.append(statement)
		let location = inner.first().location
		let body = ast.compound(inner, location)

		ast.function_def(is_pub, name: name_at.name, docstring, type_parameters, this_parameter, parameters, return_type: info.return_type, except_type: info.except_type, body, location: name_at.location)

	fn parse_extern_func_def(libname: str) -> ast.FunctionDef except CompilationError:
		let is_pub = true
		let name_at = parse_name()
		let name: str = name_at.name
		let type_parameters = parse_type_parameters()
		let parameters = parse_parameters()
		let info = parse_function_info()
		let docstring: Option[str] = Option.None()
		parse_newline()
		ast.extern_function_def(is_pub, libname, name, docstring, type_parameters, parameters, return_type: info.return_type, location: name_at.location)

	fn parse_func_decl_def(this_parameter: Option[ast.ParameterDef]) -> ast.FunctionDef except CompilationError:
		let name_at = parse_name()
		let type_parameters = parse_type_parameters()
		let parameters = parse_parameters()
		let info = parse_function_info()
		parse_newline()
		ast.function_decl_def(name: name_at.name, type_parameters, this_parameter, parameters, return_type: info.return_type, except_type: info.except_type, location: name_at.location)

	fn parse_parameters() -> List[ast.ParameterDef] except CompilationError:
		let parameters: List[ast.ParameterDef] = List()
		parse_parenthesis_open()
		# ')' or parameters and ')'
		case m_peek.kind:
			ParenthesisClose:
				move_token()
		else:
			loop:
				parameters.append(parse_parameter_def())
				let tok = get_token()
				case tok.kind:
					ParenthesisClose:
						break
					Comma:
						pass
				else:
					raise unexpected_token(tok, expected: "')' or ','")
		parameters

	fn parse_function_info() -> ast.FunctionInfo except CompilationError:
		let return_type = parse_optional_return_type()
		let except_type = parse_optional_except_type()
		ast.FunctionInfo(return_type, except_type)

	fn parse_optional_return_type() -> ast.Type except CompilationError:
		# Optional return type
		case m_peek.kind:
			Arrow:
				move_token()
				parse_type()
		else:
			id_gen.m_void_type

	fn parse_optional_except_type() -> ast.Type except CompilationError:
		# Optional except type
		case m_peek.kind:
			KwExcept:
				move_token()
				parse_type()
		else:
			id_gen.m_void_type

	fn parse_parameter_def() -> ast.ParameterDef except CompilationError:
		let name_at = parse_name()
		# Parse optional '?' to indicate label is optional at call-site
		let label_is_optional = has_parsed_question()
		parse_colon()
		let ty = parse_type()
		ast.parameter_def(name: name_at.name, id: new_id(), label_is_optional, ty, location: name_at.location)

	fn parse_optional_docstring() -> Option[str] except CompilationError:
		case m_peek.kind:
			DocString(value):
				move_token()
				parse_newline()
				Option.Some(value)
		else:
			Option.None()

	fn has_parsed_question() -> bool:
		case m_peek.kind:
			Question:
				move_token()
				true
		else:
			false

	fn parse_var_def(is_pub: bool) -> ast.VariableDef except CompilationError:
		let name_at = parse_name()
		let name = name_at.name
		parse_colon()
		let ty = parse_type()

		# Optional '=' <expr>
		let var_init: Option[ast.Expression] = case m_peek.kind:
			Equals:
				move_token()
				Option.Some(parse_big_expression())
		else:
			parse_newline()
			Option.None()

		var variable = ast.variable(name, id: new_id(), ty, location: name_at.location)
		variable.writable = true
		ast.VariableDef(is_pub, variable, value: ast.VariableDefValue.Intern(value: var_init))

	fn parse_type() -> ast.Type except CompilationError:
		let tok = get_token()
		case tok.kind:
			KwFn:
				parse_function_type()
			BracketOpen:
				parse_array_type()
			Identifier(name):
				let qname = parse_qual_name(name, location: tok.location)
				case m_peek.kind:
					BracketOpen:
						move_token()
						parse_type_application(name: qname)
				else:
					ast.new_type(kind: ast.TypeKind.NameRef(name: qname))
		else:
			raise unexpected_token(tok, expected: "identifier, 'fn' or '['")

	fn parse_qual_name(name: str, location: Location) -> ast.QualName except CompilationError:
		let parts: List[str] = List()
		parts.append(name)
		loop:
			case m_peek.kind:
				Dot:
					move_token()
					let name2_at = parse_name()
					parts.append(name2_at.name)
			else:
				break
		ast.QualName(location, parts)

	fn parse_type_application(name: ast.QualName) -> ast.Type except CompilationError:
		""" Parse type application """
		let tycon = ast.TyCon.NameRef(name)
		let type_arguments: Vector[ast.Type] = new_vector()
		loop:
			let type_argument = parse_type()
			type_arguments.append(type_argument)
			let tok = get_token()
			case tok.kind:
				Comma:
					pass
				BracketClose:
					break
			else:
				raise unexpected_token(tok, expected: "',' or ']'")
		# ast.apply_tycon(tycon, type_arguments)
		ast.new_type(kind: ast.TypeKind.App(tycon, type_arguments))

	fn parse_function_type() -> ast.Type except CompilationError:
		""" Parse function signature. """
		# '('
		parse_parenthesis_open()

		let parameter_types: Vector[ast.ParameterType] = new_vector()
		# ')' or parameters and ')'
		case m_peek.kind:
			ParenthesisClose:
				move_token()
		else:
			loop:
				let label: Option[str] = Option.None()
				let param_type = parse_type()
				parameter_types.append(ast.ParameterType(label, ty: param_type))

				let tok4 = get_token()
				case tok4.kind:
					ParenthesisClose:
						break
					Comma:
						continue
				else:
					raise unexpected_token(tok: tok4, expected: "')' or ','")

		# Optional return type
		let return_type = parse_optional_return_type()
		let except_type = id_gen.m_void_type

		let info = ast.FunctionInfo:
			return_type
			except_type

		ast.function_type(parameter_types, info)

	fn parse_array_type() -> ast.Type except CompilationError:
		""" Parse array type """
		let element_type = parse_type()
		let tok = get_token()
		case tok.kind:
			BracketClose:
				pass
		else:
			raise unexpected_token(tok, expected: "']'")
		ast.array_type(element_type, size: 0)

	fn parse_block() -> ast.Statement except CompilationError:
		""" parse block of statements. """
		log_trace("parsing block")

		parse_colon()
		parse_newline()
		parse_indent()

		let inner: Vector[ast.Statement] = new_vector()
		while not try_parse_dedent():
			let statement = parse_statement()
			inner.append(statement)
		let location = inner.first().location
		ast.compound(inner, location)

	pub fn parse_statement() -> ast.Statement except CompilationError:
		log_trace("parsing statement")
		case m_peek.kind:
			KwPass:
				let location = get_token().location
				parse_newline()
				ast.pass_statement(location)
			KwBreak:
				let location = get_token().location
				parse_newline()
				ast.break_statement(location)
			KwContinue:
				let location = get_token().location
				parse_newline()
				ast.continue_statement(location)
			KwLet:
				parse_let_statement(writable: false)
			KwVar:
				parse_let_statement(writable: true)
			KwIf:
				parse_if_statement()
			KwLoop:
				let location = get_token().location
				let body = parse_block()
				ast.loop_statement(body, location)
			KwWhile:
				parse_while_statement()
			KwCase:
				parse_case_statement()
			KwSwitch:
				parse_switch_statement()
			KwFor:
				parse_for_statement()
			KwTry:
				parse_try_statement()
			KwReturn:
				parse_return_statement()
			KwRaise:
				parse_raise_statement()
		else:
			parse_expression_statement()

	fn parse_expression_statement() -> ast.Statement except CompilationError:
		let expr = parse_expression()

		# Maybe we have an assignment or object initializer
		let tok = get_token()
		case tok.kind:
			Equals:
				parse_assignement_expression(target: expr, op: Option.None(), location: tok.location)
			PlusEquals:
				parse_assignement_expression(target: expr, op: Option.Some(ast.BinaryOperator.Add()), location: tok.location)
			MinusEquals:
				parse_assignement_expression(target: expr, op: Option.Some(ast.BinaryOperator.Sub()), location: tok.location)
			AsterixEquals:
				parse_assignement_expression(target: expr, op: Option.Some(ast.BinaryOperator.Mul()), location: tok.location)
			SlashEquals:
				parse_assignement_expression(target: expr, op: Option.Some(ast.BinaryOperator.Div()), location: tok.location)
			NewLine:
				ast.expression_statement(expr)
			Colon:
				ast.expression_statement(expr: parse_obj_init(obj_ty: expr, location: tok.location))
		else:
			raise unexpected_token(tok, expected: "newline, ':', '=', '+=', '-=', '*=' or '/='")

	fn parse_assignement_expression(target: ast.Expression, op: Option[ast.BinaryOperator], location: Location) -> ast.Statement except CompilationError:
		let value = parse_expression()
		parse_newline()
		ast.assignment_statement(target, op, value, location)

	fn parse_let_statement(writable: bool) -> ast.Statement except CompilationError:
		let location = get_token().location
		let name_at = parse_name()
		let var_name = name_at.name
		let var_type = ast.undefined_type()
		let variable = ast.variable(name: var_name, id: new_id(), ty: var_type, location: name_at.location)
		variable.writable = writable

		let type_hint: Option[ast.Type] = case m_peek.kind:
			Colon:
				move_token()
				# Type hint!
				Option.Some(parse_type())
		else:
			Option.None()

		parse_equals()
		let value = parse_big_expression()
		ast.let_statement(variable, type_hint, value, location)

	fn parse_big_expression() -> ast.Expression except CompilationError:
		""" A potentially big multi-line expression occurring at the end of the line. """
		case m_peek.kind:
			KwIf:
				ast.statement_expression(statement: parse_if_statement())
			KwCase:
				ast.statement_expression(statement: parse_case_statement())
			KwSwitch:
				ast.statement_expression(statement: parse_switch_statement())
		else:
			let value = parse_expression()

			let tok = get_token()
			case tok.kind:
				NewLine:
					value
				Colon:
					parse_obj_init(obj_ty: value, location: tok.location)
			else:
				raise unexpected_token(tok, expected: "newline or ':'")

	fn parse_obj_init(obj_ty: ast.Expression, location: Location) -> ast.Expression except CompilationError:
		# Obj initializer!
		parse_newline()
		parse_indent()

		let obj_fields: List[ast.LabeledExpression] = List()
		while not try_parse_dedent():
			obj_fields.append(parse_labeled_expression())
			parse_newline()
		ast.call(callee: obj_ty, arguments: obj_fields, ty: ast.undefined_type(), location)

	fn parse_labeled_expression() -> ast.LabeledExpression except CompilationError:
		# Parse ID ':' expression | expression
		case m_peek.kind:
			Identifier(name):
				case m_peek2.kind:
					Colon:
						let location = m_peek.location
						move_token()
						move_token()
						# Parse ID ':' expression
						let value = parse_expression()
						return ast.LabeledExpression(location, name: Option.Some(name), value)
				else:
					pass
		else:
			pass

		# Parse expression
		let value = parse_expression()
		let name: Option[str] = case value.kind:
			NameRef(name2):
				Option.Some(name2)
		else:
			Option.None()
		ast.LabeledExpression(location: value.location, name, value)

	fn parse_if_statement() -> ast.Statement except CompilationError:
		# Parse if-statement
		let location = get_token().location

		let condition = parse_expression()
		let true_block = parse_block()

		# else-block or elif-block:
		let false_block = case m_peek.kind:
			KwElse:
				move_token()
				parse_block()
			KwElif:
				parse_if_statement()
		else:
			ast.pass_statement(location)

		ast.if_statement(condition, body: true_block, false_body: false_block, location)

	fn parse_while_statement() -> ast.Statement except CompilationError:
		let location = get_token().location
		let condition = parse_expression()
		let body = parse_block()
		ast.while_statement(condition, body, location)

	fn parse_for_statement() -> ast.Statement except CompilationError:
		let location = get_token().location
		let name_at = parse_name()

		# 'in'
		let tok2 = get_token()
		case tok2.kind:
			KwIn:
				pass
		else:
			raise unexpected_token(tok: tok2, expected: "'in'")

		let iter_value = parse_expression()

		# ':' + indented block:
		let body = parse_block()
		let iter_var = ast.variable(name: name_at.name, id: new_id(), ty: ast.undefined_type(), location: name_at.location)
		ast.for_statement(iter_var, iter_value, body, location)

	fn parse_try_statement() -> ast.Statement except CompilationError:
		let location = get_token().location
		let try_body = parse_block()

		# 'except'
		let tok = get_token()
		case tok.kind:
			KwExcept:
				pass
		else:
			raise unexpected_token(tok, expected: "'except'")

		parse_parenthesis_open()
		let name_at = parse_name()
		parse_colon()
		let except_type = parse_type()
		parse_parenthesis_close()
		let except_var = ast.variable(name: name_at.name, id: new_id(), ty: ast.undefined_type(), location: name_at.location)

		let except_body = parse_block()
		ast.try_statement(try_body, except_var, except_type, except_body, location)

	fn parse_case_statement() -> ast.Statement except CompilationError:
		let location = get_token().location

		# Value
		let case_value = parse_expression()
		parse_colon()
		parse_newline()
		parse_indent()

		let case_arms: List[ast.CaseArm] = List()
		while not try_parse_dedent():
			let name_at = parse_name()
			case_arms.append(parse_case_arm(name: name_at.name, location: name_at.location))

		# Parse optional 'else' block
		let else_clause = case m_peek.kind:
			KwElse:
				move_token()
				Option.Some(parse_block())
		else:
			Option.None()

		ast.case_statement(value: case_value, arms: case_arms, else_clause, location)

	fn parse_case_arm(name: str, location: Location) -> ast.CaseArm except CompilationError:
		let variables: List[ast.Variable] = List()
		# Eventual payload values to unpack:
		case m_peek.kind:
			ParenthesisOpen:
				move_token()
				loop:
					let name_at = parse_name()
					let variable = ast.variable(name: name_at.name, id: new_id(), ty: ast.undefined_type(), location: name_at.location)
					variables.append(variable)

					let tok = get_token()
					case tok.kind:
						ParenthesisClose:
							break
						Comma:
							continue
					else:
						raise unexpected_token(tok, expected: "',' or ')'")
		else:
			pass

		# Arm body:
		let statement = parse_block()
		ast.CaseArm:
			location
			name
			variables: variables
			block: ast.scoped_block(body: statement)

	fn parse_switch_statement() -> ast.Statement except CompilationError:
		let location = get_token().location
		let switch_value = parse_expression()
		parse_colon()
		parse_newline()
		parse_indent()
		let arms: List[ast.SwitchArm] = List()
		while not try_parse_dedent():
			let value = parse_expression()
			let block = ast.scoped_block(body: parse_block())
			arms.append(ast.SwitchArm(location: value.location, value, block))

		parse_kw_else()
		let default_body = parse_block()
		ast.switch_statement(value: switch_value, arms, default_body, location)

	fn parse_return_statement() -> ast.Statement except CompilationError:
		# optionally parse expression (or newline)!
		let location = get_token().location
		let res_value: Option[ast.Expression] = case m_peek.kind:
			NewLine:
				move_token()
				Option.None()
		else:
			let ret_val = parse_expression()
			parse_newline()
			Option.Some(ret_val)
		ast.return_statement(value: res_value, location)

	fn parse_raise_statement() -> ast.Statement except CompilationError:
		let location = get_token().location
		let value = parse_expression()
		parse_newline()
		ast.raise_statement(value, location)

	pub fn parse_expression() -> ast.Expression except CompilationError:
		# log_trace("Parsing expression")
		parse_expression2(min_prec: 0)

	fn parse_expression2(min_prec: int) -> ast.Expression except CompilationError:
		var expr = parse_unary()

		loop:
			# Determine next token and new precedence
			var prec = 0
			let op: ast.BinaryOperator = case m_peek.kind:
				KwOr:
					prec = 20
					ast.BinaryOperator.Or()
				KwAnd:
					prec = 25
					ast.BinaryOperator.And()
				Less:
					prec = 30
					ast.BinaryOperator.Less()
				LessEquals:
					prec = 30
					ast.BinaryOperator.LessEquals()
				Greater:
					prec = 30
					ast.BinaryOperator.Greater()
				GreaterEquals:
					prec = 30
					ast.BinaryOperator.GreaterEquals()
				EqualsEquals:
					prec = 30
					ast.BinaryOperator.Equals()
				NotEquals:
					prec = 30
					ast.BinaryOperator.NotEquals()
				BitOr:
					prec = 51
					ast.BinaryOperator.BitOr()
				BitXor:
					prec = 52
					ast.BinaryOperator.BitXor()
				BitAnd:
					prec = 53
					ast.BinaryOperator.BitAnd()
				ShiftLeft:
					prec = 55
					ast.BinaryOperator.ShiftLeft()
				ShiftRight:
					prec = 55
					ast.BinaryOperator.ShiftRight()
				Plus:
					prec = 60
					ast.BinaryOperator.Add()
				Minus:
					prec = 60
					ast.BinaryOperator.Sub()
				Slash:
					prec = 80
					ast.BinaryOperator.Div()
				Asterix:
					prec = 80
					ast.BinaryOperator.Mul()
			else:
				break

			if prec < min_prec:
				break

			move_token()

			let rhs = parse_expression2(min_prec: prec + 1)
			let location = Location(begin: expr.location.begin, end: rhs.location.end)
			expr = ast.binop(lhs: expr, op, rhs, ty: ast.undefined_type(), location)

		expr

	fn parse_unary() -> ast.Expression except CompilationError:
		case m_peek.kind:
			KwNot:
				let location = m_peek.location
				move_token()
				let value = parse_unary()
				let op = ast.UnaryOperator.Not()
				ast.unop(op, value, ty: ast.undefined_type(), location)
			Minus:
				let location = m_peek.location
				move_token()
				let value = parse_unary()
				let op = ast.UnaryOperator.Minus()
				ast.unop(op, value, ty: ast.undefined_type(), location)
		else:
			parse_atom()

	fn parse_atom() -> ast.Expression except CompilationError:
		let tok = get_token()
		var expr = case tok.kind:
			Integer(value):
				ast.integer_literal(value, location: tok.location)
			Float(value):
				ast.float_literal(value, location: tok.location)
			StringStart:
				parse_string(location: tok.location)
			Char(value):
				ast.char_literal(value, location: tok.location)
			Bool(value):
				ast.bool_literal(value, location: tok.location)
			Identifier(name):
				ast.name_ref(name, location: tok.location)
			ParenthesisOpen:
				let expr = parse_expression()
				parse_parenthesis_close()
				expr
			BracketOpen:
				parse_array_literal(location: tok.location)
		else:
			raise unexpected_token(tok, expected: "integer, string, identifier, '('")

		# Attempt suffixes
		loop:
			case m_peek.kind:
				Dot:
					move_token()
					# handle '.attribute' suffix
					let attr_at = parse_name()
					let location = Location(begin: expr.location.begin, end: attr_at.location.end)
					expr = ast.get_attr(base: expr, field: attr_at.name, ty: ast.undefined_type(), location)
				ParenthesisOpen:
					move_token()
					expr = parse_call_suffix(callee: expr)
				BracketOpen:
					move_token()
					expr = parse_index_suffix(base: expr)
			else:
				break
		expr

	fn parse_raw_string() -> str except CompilationError:
		""" Parse string without interpolation """
		var tok = get_token()
		case tok.kind:
			StringStart:
				pass
		else:
			raise unexpected_token(tok, expected: "string start")

		tok = get_token()
		let text = case tok.kind:
			StringContent(value):
				value
		else:
			raise unexpected_token(tok, expected: "string content")

		tok = get_token()
		case tok.kind:
			StringEnd:
				pass
		else:
			raise unexpected_token(tok, expected: "string end")

		text

	fn parse_string(location: Location) -> ast.Expression except CompilationError:
		""" Parse possibly interpolated string. """
		# Gather parts
		let parts: List[ast.Expression] = List()
		loop:
			let tok = get_token()
			case tok.kind:
				StringContent(value):
					let raw_string_expr = ast.string_literal(value, location: tok.location)
					parts.append(raw_string_expr)

				BraceOpen:
					let value = parse_expression()
					let to_string_expr = ast.to_string(value, location: value.location)
					parts.append(to_string_expr)
					parse_brace_close()

				StringEnd:
					break
			else:
				raise unexpected_token(tok, expected: "String content, '\"' or '\{'")

		# Concatenate parts
		if parts.is_empty():
			ast.string_literal(value: "", location)
		else:
			var x = parts.pop_front()
			while not parts.is_empty():
				let rhs = parts.pop_front()
				let location = Location(begin: x.location.begin, end: rhs.location.end)
				x = ast.binop(lhs: x, op: ast.BinaryOperator.Add(), rhs, ty: ast.str_type(), location)
			x

	fn parse_index_suffix(base: ast.Expression) -> ast.Expression except CompilationError:
		let begin = base.location.begin
		var end = base.location.end
		let indici: List[ast.Expression] = List()
		loop:
			indici.append(parse_expression())
			let tok4 = get_token()
			case tok4.kind:
				BracketClose:
					end = tok4.location.end
					break
				Comma:
					continue
			else:
				raise unexpected_token(tok: tok4, expected: "']' or ','")
		let location = Location(begin, end)
		ast.subscript(base, indici, ty: ast.undefined_type(), location)

	fn parse_call_suffix(callee: ast.Expression) -> ast.Expression except CompilationError:
		# print("CALL")
		# Handle '(arg1,arg2)' suffix
		# Or '()' or '(arg1)'
		let arguments: List[ast.LabeledExpression] = List()
		let begin = callee.location.begin
		var end = m_peek.location.end
		case m_peek.kind:
			ParenthesisClose:
				# no args call
				move_token()
		else:
			# call with parameters

			loop:
				arguments.append(parse_labeled_expression())
				let tok4 = get_token()
				case tok4.kind:
					ParenthesisClose:
						end = tok4.location.end
						break
					Comma:
						continue
				else:
					raise unexpected_token(tok: tok4, expected: "')' or ','")

		let location = Location(begin, end)
		ast.call(callee, arguments, ty: ast.undefined_type(), location)

	fn parse_array_literal(location: Location) -> ast.Expression except CompilationError:
		let values: List[ast.Expression] = List()
		loop:
			let value = parse_expression()
			values.append(value)

			let tok5 = get_token()
			case tok5.kind:
				BracketClose:
					location = Location(begin: location.begin, end: tok5.location.end)
					break
				Comma:
					continue
				Colon:
					return parse_array_literal2(size: value, location)
			else:
				raise unexpected_token(tok: tok5, expected: "',', ':' or ']'")
		ast.array_literal(values, location)

	fn parse_array_literal2(size: ast.Expression, location: Location) -> ast.Expression except CompilationError:
		let ty = parse_type()
		let tok5 = get_token()
		case tok5.kind:
			BracketClose:
				pass
		else:
			raise unexpected_token(tok: tok5, expected: "']'")

		location = Location(begin: location.begin, end: tok5.location.end)
		ast.array_literal2(size, ty, location)

	fn parse_name() -> ast.NameAtLocation except CompilationError:
		let tok = get_token()
		case tok.kind:
			Identifier(name):
				ast.NameAtLocation(name, location: tok.location)
		else:
			raise unexpected_token(tok, expected: "name")

	fn parse_parenthesis_open() except CompilationError:
		let tok = get_token()
		case tok.kind:
			ParenthesisOpen:
				pass
		else:
			raise unexpected_token(tok, expected: "'('")

	fn parse_parenthesis_close() except CompilationError:
		let tok = get_token()
		case tok.kind:
			ParenthesisClose:
				pass
		else:
			raise unexpected_token(tok, expected: "')'")

	fn parse_brace_close() except CompilationError:
		let tok = get_token()
		case tok.kind:
			BraceClose:
				pass
		else:
			raise unexpected_token(tok, expected: "'}'")

	fn parse_newline() except CompilationError:
		let tok = get_token()
		case tok.kind:
			NewLine:
				pass
		else:
			raise unexpected_token(tok, expected: "newline")

	fn parse_indent() except CompilationError:
		let tok = get_token()
		case tok.kind:
			Indent:
				pass
		else:
			raise unexpected_token(tok, expected: "indent")

	fn parse_dedent() except CompilationError:
		let tok = get_token()
		case tok.kind:
			Dedent:
				pass
		else:
			raise unexpected_token(tok, expected: "dedent")

	fn try_parse_dedent() -> bool:
		# expect dedent (eventually)
		case m_peek.kind:
			Dedent:
				move_token()
				true
		else:
			false

	fn parse_kw_else() except CompilationError:
		let tok = get_token()
		case tok.kind:
			KwElse:
				pass
		else:
			raise unexpected_token(tok, expected: "'else'")

	fn parse_kw_for() except CompilationError:
		let tok = get_token()
		case tok.kind:
			KwFor:
				pass
		else:
			raise unexpected_token(tok, expected: "'for'")

	fn parse_colon() except CompilationError:
		case m_peek.kind:
			Colon:
				move_token()
		else:
			raise unexpected_token(tok: m_peek, expected: "':'")

	fn parse_equals() except CompilationError:
		case m_peek.kind:
			Equals:
				move_token()
		else:
			raise unexpected_token(tok: m_peek, expected: "'='")

	fn move_token():
		m_peek = m_peek2
		m_peek2 = lex.next_token()

	fn get_token() -> Token:
		let tok = m_peek
		move_token()
		tok

	fn new_id() -> int:
		id_gen.new_id()

	fn unexpected_token(tok: Token, expected: str) -> CompilationError:
		new_error(location: tok.location, message: "Expected {expected}, got {token_to_string(tok)}")

	fn new_error(location: Location, message: str) -> CompilationError:
		let err = errors.new_error(location, message)
		errors.new_errors(filename: filename, errors: list1(err))
