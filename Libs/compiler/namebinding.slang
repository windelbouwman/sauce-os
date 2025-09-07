
from utils import log_info, log_trace
from location import Location, location_default
from listtype import List
from optiontype import Option, option_is_some
from hashmap import HashMap, new_hashmap_str
import ast
from errors import CompilationError, SingleCompilationError, ErrorCollector

pub fn bind_names(module: ast.ModuleDef, module_map: HashMap[str,ast.ModuleDef]) except CompilationError:
	let tycon_map: HashMap[ast.NodeId,ast.TyCon] = ast.new_hashmap_nodeid()
	log_info("Filling scopes for {module.name}")
	let binder = NameBinder(module_map, tycon_map)
	let fill_visitor: ast.Visitor[NameBinder] = ast.Visitor:
		data: binder
		on_definition: filler_on_definition
		on_type: filler_on_type
		on_statement: filler_on_statement
		on_expression: filler_on_expression
		on_node: filler_on_node
	binder.enter_scope(scope: module.scope)
	ast.visit_module(visitor: fill_visitor, module)
	binder.leave_scope()
	binder.render_or_raise()

	# Now import symbols
	log_info("Resolving imported symbols")
	let import_visitor = new_import_visitor(binder)
	ast.visit_module(visitor: import_visitor, module)

	log_info("Binding names for {module.name}")
	let bind_visitor = new_bind_visitor(binder)
	binder.enter_scope(scope: base_scope())
	binder.enter_scope(scope: module.scope)
	ast.visit_module(visitor: bind_visitor, module)
	binder.leave_scope()
	binder.leave_scope()

	let used_symbol_visitor = new_used_symbol_visitor(binder)
	ast.visit_module(visitor: used_symbol_visitor, module)
	binder.render_or_raise()

fn new_bind_visitor(binder: NameBinder) -> ast.Visitor[NameBinder]:
	ast.Visitor:
		data: binder
		on_definition: binder_on_definition
		on_type: binder_on_type
		on_statement: binder_on_statement
		on_expression: binder_on_expression
		on_node: binder_on_node

pub fn bind_names_expression(expression: ast.Expression) except CompilationError:
	let module_map: HashMap[str,ast.ModuleDef] = new_hashmap_str()
	let tycon_map: HashMap[ast.NodeId,ast.TyCon] = ast.new_hashmap_nodeid()
	let binder = NameBinder(module_map, tycon_map)
	let bind_visitor = new_bind_visitor(binder)
	ast.visit_expression(visitor: bind_visitor, expression)
	binder.render_or_raise()

fn get_scope(definition: ast.Definition) -> Option[ast.Scope]:
	# try to retrieve a scope, if we have one
	case definition:
		Module(module):
			Option.Some(module.scope)
		Macro(macro_def):
			Option.None()
		Function(function_def):
			case function_def.body:
				Intern(scoped_block):
					Option.Some(scoped_block.scope)
				Extern(libname):
					Option.None()
				None:
					Option.None()
		Enum(enum_def):
			Option.Some(enum_def.scope)
		Struct(struct_def):
			Option.Some(struct_def.scope)
		Class(class_def):
			Option.Some(class_def.scope)
		Interface(interface_def):
			Option.Some(interface_def.scope)
		Impl(impl_def):
			Option.Some(impl_def.scope)
		Var(v):
			Option.None()
		Type(type_def):
			Option.None()

fn filler_on_definition(filler: NameBinder, definition: ast.Definition, phase: ast.VisitPhase):
	case phase:
		Pre:
			case definition:
				Module(module_def):
					log_info("Entering module {module_def.name}")
					#filler.define(is_pub: true, name: module_def.name, kind: ast.SymbolKind.Module(module_def), location: module_def.location)
					filler.enter_scope(scope: module_def.scope)
				Macro(macro_def):
					filler.define(is_pub: false, name: macro_def.name, kind: ast.SymbolKind.Macro(macro_def), location: macro_def.location)
				Function(function_def):
					filler.define(is_pub: function_def.is_pub, name: function_def.name, kind: ast.SymbolKind.Function(function_def), location: function_def.location)
					case function_def.body:
						Intern(scoped_block):
							filler.enter_scope(scope: scoped_block.scope)
							for type_parameter in function_def.type_parameters:
								filler.define_type_parameter(type_parameter)
							for parameter_def in function_def.parameters:
								filler.define_parameter(parameter_def)
							case function_def.this_parameter:
								Some(this_parameter2):
									filler.define_parameter(parameter_def: this_parameter2)
								None:
									pass
						Extern(libname):
							pass
						None:
							pass
				Enum(enum_def):
					let tycon = ast.TyCon.Enum(enum_def)
					filler.add_tycon(id: enum_def.id, tycon)
					filler.define(is_pub: enum_def.is_pub, name: enum_def.id.name, kind: ast.SymbolKind.TypeConstructor(tycon), location: enum_def.location)
					filler.enter_scope(scope: enum_def.scope)
					for type_parameter in enum_def.type_parameters:
						filler.define_type_parameter(type_parameter)
					for variant in enum_def.variants:
						filler.define(is_pub: false, name: variant.name, kind: ast.SymbolKind.Variant(variant), location: variant.location)
				Struct(struct_def):
					let tycon = ast.TyCon.Struct(struct_def)
					filler.add_tycon(id: struct_def.id, tycon)
					filler.define(is_pub: struct_def.is_pub, name: struct_def.id.name, kind: ast.SymbolKind.TypeConstructor(tycon), location: struct_def.location)
					filler.enter_scope(scope: struct_def.scope)
					for type_parameter in struct_def.type_parameters:
						filler.define_type_parameter(type_parameter)
					for field in struct_def.fields:
						filler.define(is_pub: false, name: field.name, kind: ast.SymbolKind.Field(field), location: field.location)
				Class(class_def):
					let tycon = ast.TyCon.Class(class_def)
					filler.add_tycon(id: class_def.id, tycon)
					filler.define(is_pub: class_def.is_pub, name: class_def.id.name, kind: ast.SymbolKind.TypeConstructor(tycon), location: class_def.location)
					filler.enter_scope(scope: class_def.scope)
					for type_parameter in class_def.type_parameters:
						filler.define_type_parameter(type_parameter)
				Interface(interface_def):
					let tycon = ast.TyCon.Interface(interface_def)
					filler.add_tycon(id: interface_def.id, tycon)
					filler.define(is_pub: interface_def.is_pub, name: interface_def.id.name, kind: ast.SymbolKind.TypeConstructor(tycon), location: interface_def.location)
					filler.enter_scope(scope: interface_def.scope)
				Impl(impl_def):
					filler.enter_scope(scope: impl_def.scope)
				Var(variable_def):
					filler.define_variable(is_pub: variable_def.is_pub, variable: variable_def.variable)
				Type(type_def):
					let typ = ast.new_type(kind: ast.TypeKind.Def(type_def))
					filler.define(is_pub: type_def.is_pub, name: type_def.id.name, kind: ast.SymbolKind.Typ(typ), location: type_def.location)
		Post:
			case get_scope(definition):
				None:
					pass
			else:
				filler.leave_scope()
	else:
		pass

fn filler_on_type(filler: NameBinder, ty: ast.Type, phase: ast.VisitPhase):
	pass

fn filler_on_statement(filler: NameBinder, statement: ast.Statement, phase: ast.VisitPhase):
	case phase:
		Pre:
			case statement.kind:
				Let(letty):
					filler.define_variable(is_pub: true, variable: letty.variable)
				For(for_statement):
					filler.enter_scope(scope: for_statement.block.scope)
					filler.define_variable(is_pub: true, variable: for_statement.iter_var)
				While(while_statement):
					filler.enter_scope(scope: while_statement.block.scope)
				Loop(loop_statement):
					filler.enter_scope(scope: loop_statement.block.scope)
				Try(try_statement):
					# TODO: create new scope for except clause?
					filler.define_variable(is_pub: true, variable: try_statement.except_var)
			else:
				pass
		Post:
			case statement.kind:
				For(for_statement):
					filler.leave_scope()
				While(while_statement):
					filler.leave_scope()
				Loop(loop_statement):
					filler.leave_scope()
			else:
				pass
	else:
		pass

fn filler_on_expression(filler: NameBinder, expression: ast.Expression, phase: ast.VisitPhase):
	pass

fn filler_on_node(filler: NameBinder, node: ast.VisitNode, phase: ast.VisitPhase):
	case phase:
		Pre:
			case node:
				Arm(arm):
					filler.enter_scope(scope: arm.block.scope)
					for variable in arm.variables:
						filler.define_variable(is_pub: true, variable)
				ScopeNode(scope):
					filler.enter_scope(scope)
			else:
				pass
		Post:
			case node:
				Arm(arm):
					filler.leave_scope()
				ScopeNode(scope):
					filler.leave_scope()
			else:
				pass
	else:
		pass

fn new_import_visitor(binder: NameBinder) -> ast.Visitor[NameBinder]:
	ast.Visitor:
		data: binder
		on_definition: importer_on_definition
		on_type: importer_on_type
		on_statement: importer_on_statement
		on_expression: importer_on_expression
		on_node: importer_on_node

fn importer_on_definition(binder: NameBinder, definition: ast.Definition, phase: ast.VisitPhase):
	case phase:
		Pre:
			case definition:
				Module(module_def):
					log_info("Importing symbols into module {module_def.name}")
					binder.enter_scope(scope: module_def.scope)
					binder.errors.enter_file(filename: module_def.filename)
					for imp in module_def.imports:
						binder.import_mod(imp)
			else:
				pass
		Post:
			case definition:
				Module(module_def):
					binder.leave_scope()
					binder.errors.leave_file()
			else:
				pass
	else:
		pass

fn importer_on_type(binder: NameBinder, ty: ast.Type, phase: ast.VisitPhase):
	pass

fn importer_on_statement(binder: NameBinder, statement: ast.Statement, phase: ast.VisitPhase):
	pass

fn importer_on_expression(binder: NameBinder, expression: ast.Expression, phase: ast.VisitPhase):
	pass

fn importer_on_node(binder: NameBinder, node: ast.VisitNode, phase: ast.VisitPhase):
	pass

fn binder_on_definition(binder: NameBinder, definition: ast.Definition, phase: ast.VisitPhase):
	case phase:
		Pre:
			case get_scope(definition):
				None:
					pass
				Some(scope):
					binder.enter_scope(scope)
			case definition:
				Module(module_def):
					binder.errors.enter_file(filename: module_def.filename)
			else:
				pass
		Post:
			case get_scope(definition):
				None:
					pass
			else:
				binder.leave_scope()
			case definition:
				Module(module_def):
					binder.errors.leave_file()
			else:
				pass
	else:
		pass

fn binder_on_type(binder: NameBinder, ty: ast.Type, phase: ast.VisitPhase):
	case phase:
		Post:
			try:
				case ty.kind:
					App(tycon, type_arguments):
						case tycon:
							Ref(key):
								# if not binder.tycon_map.contains(key):
								#     panic("No tycon: {ast.node_id_to_string(key)}")
								let tycon = binder.tycon_map.get(key)
								ty.kind = ast.TypeKind.App(tycon, type_arguments)
							NameRef(name):
									let tycon = binder.resolve_tycon(name)
									let type_parameters = ast.tycon_get_type_parameters(tycon)
									if type_parameters.len() == type_arguments.len():
										ty.kind = ast.TypeKind.App(tycon, type_arguments)
									else:
										binder.add_error(location: name.location, message: "Got {type_arguments.len()} type arguments, expected {type_parameters.len()}")
						else:
							pass
					NameRef(name):
						ty.kind = binder.resolve_type_kind(name)
				else:
					pass
			except (error: SingleCompilationError):
				binder.errors.append(error)
	else:
		pass

fn binder_on_statement(binder: NameBinder, statement: ast.Statement, phase: ast.VisitPhase):
	case phase:
		Pre:
			case statement.kind:
				For(for_statement):
					binder.enter_scope(scope: for_statement.block.scope)
				While(while_statement):
					binder.enter_scope(scope: while_statement.block.scope)
				Loop(loop_statement):
					binder.enter_scope(scope: loop_statement.block.scope)
			else:
				pass
		Post:
			case statement.kind:
				For(for_statement):
					binder.leave_scope()
				While(while_statement):
					binder.leave_scope()
				Loop(loop_statement):
					binder.leave_scope()
			else:
				pass
	else:
		pass

fn symbol_to_kind(symbol: ast.Symbol) -> ast.ExpressionKind:
	case symbol.kind:
		Typ(ty):
			ast.ExpressionKind.Typ(ty)
		TypeConstructor(tycon):
			ast.ExpressionKind.Typ(ty: ast.new_type(kind: ast.TypeKind.UnApp(tycon)))
		Var(variable):
			ast.ExpressionKind.VariableRef(variable)
		Parameter(parameter_def):
			ast.ExpressionKind.ParameterRef(parameter_def)
	else:
		ast.ExpressionKind.LoadSymbol(symbol)

fn binder_on_expression(binder: NameBinder, expression: ast.Expression, phase: ast.VisitPhase):
	case phase:
		Post:
			try:
				case expression.kind:
					NameRef(name):
						expression.kind = binder.lookup_expression_kind(name, location: expression.location)
					GetAttr(base, attr):
						case base.kind:
							LoadSymbol(sym):
								case sym.kind:
									Module(module):
										let symbol = binder.resolve_attribute(module, attr, location: expression.location)
										expression.kind = symbol_to_kind(symbol)
								else:
									pass
						else:
							pass
				else:
					pass
			except (error: SingleCompilationError):
				binder.errors.append(error)
	else:
		pass

fn binder_on_node(binder: NameBinder, node: ast.VisitNode, phase: ast.VisitPhase):
	case phase:
		Pre:
			case node:
				Arm(arm):
					binder.enter_scope(scope: arm.block.scope)
				ScopeNode(scope):
					binder.enter_scope(scope)
			else:
				pass
		Post:
			case node:
				Arm(arm):
					binder.leave_scope()
				ScopeNode(scope):
					binder.leave_scope()
			else:
				pass
	else:
		pass


fn new_used_symbol_visitor(binder: NameBinder) -> ast.Visitor[NameBinder]:
	ast.Visitor:
		data: binder
		on_definition: used_symbol_on_definition
		on_type: used_symbol_on_type
		on_statement: used_symbol_on_statement
		on_expression: used_symbol_on_expression
		on_node: used_symbol_on_node

fn used_symbol_on_definition(binder: NameBinder, definition: ast.Definition, phase: ast.VisitPhase):
	case phase:
		Pre:
			case definition:
				Module(module_def):
					binder.errors.enter_file(filename: module_def.filename)

					for symbol in module_def.scope.get_symbols():
						if not symbol.is_pub and symbol.get_references() == 0:
							# TODO: use filename as a hack to reduce amount of warnings:
							if option_is_some(module_def.filename):
								binder.add_warning(location: symbol.location, message: "Symbol '{symbol.name}' defined but unused.")
			else:
				pass
		Post:
			case definition:
				Module(module_def):
					binder.errors.leave_file()
			else:
				pass
	else:
		pass

fn used_symbol_on_type(binder: NameBinder, ty: ast.Type, phase: ast.VisitPhase):
	pass

fn used_symbol_on_statement(binder: NameBinder, statement: ast.Statement, phase: ast.VisitPhase):
	pass

fn used_symbol_on_expression(binder: NameBinder, expression: ast.Expression, phase: ast.VisitPhase):
	pass

fn used_symbol_on_node(binder: NameBinder, node: ast.VisitNode, phase: ast.VisitPhase):
	pass

fn base_scope() -> ast.Scope:
	let s = ast.Scope()
	let location = location_default()
	let is_pub = true
	s.define(is_pub, name: "int", kind: ast.SymbolKind.Typ(ty: ast.int_type()), location)
	s.define(is_pub, name: "uint8", kind: ast.SymbolKind.Typ(ty: ast.uint8_type()), location)
	s.define(is_pub, name: "uint16", kind: ast.SymbolKind.Typ(ty: ast.uint16_type()), location)
	s.define(is_pub, name: "uint32", kind: ast.SymbolKind.Typ(ty: ast.uint32_type()), location)
	s.define(is_pub, name: "uint64", kind: ast.SymbolKind.Typ(ty: ast.uint64_type()), location)
	s.define(is_pub, name: "int8", kind: ast.SymbolKind.Typ(ty: ast.int8_type()), location)
	s.define(is_pub, name: "int16", kind: ast.SymbolKind.Typ(ty: ast.int16_type()), location)
	s.define(is_pub, name: "int32", kind: ast.SymbolKind.Typ(ty: ast.int32_type()), location)
	s.define(is_pub, name: "int64", kind: ast.SymbolKind.Typ(ty: ast.int64_type()), location)
	s.define(is_pub, name: "str", kind: ast.SymbolKind.Typ(ty: ast.str_type()), location)
	s.define(is_pub, name: "char", kind: ast.SymbolKind.Typ(ty: ast.char_type()), location)
	s.define(is_pub, name: "bool", kind: ast.SymbolKind.Typ(ty: ast.bool_type()), location)
	s.define(is_pub, name: "float", kind: ast.SymbolKind.Typ(ty: ast.float_type()), location)
	s.define(is_pub, name: "float32", kind: ast.SymbolKind.Typ(ty: ast.float32_type()), location)
	s.define(is_pub, name: "float64", kind: ast.SymbolKind.Typ(ty: ast.float64_type()), location)
	s.define(is_pub, name: "unreachable", kind: ast.SymbolKind.Typ(ty: ast.unreachable_type()), location)
	s

class NameBinder:
	""" Helper class to fill scopes, and resolve names from scopes. """
	var scopes: List[ast.Scope] = List()
	var module_map: HashMap[str,ast.ModuleDef]
	pub var tycon_map: HashMap[ast.NodeId,ast.TyCon]
	var was_class_scope: bool = false # HACK for multiple return values?
	pub var errors: ErrorCollector = ErrorCollector()

	pub fn import_mod(imp: ast.Import):
		log_trace("Import {imp.modname}")
		case module_map.maybe_get(key: imp.modname):
			Some(module):
				case imp.kind:
					Self:
						define(is_pub: false, name: module.name, kind: ast.SymbolKind.Module(module), location: imp.location)
					Names(names):
						for name in names:
							log_trace("Importing {name.name} from {module.name}")
							try:
								let symbol = resolve_attribute(module, attr: name.name, location: name.location)
								define(is_pub: false, name: name.name, kind: symbol.kind, location: name.location)
							except (error: SingleCompilationError):
								errors.append(error)
			None:
				add_error(location: imp.location, message: "Error, no module named: {imp.modname}")

	pub fn add_tycon(id: ast.NodeId, tycon: ast.TyCon):
		tycon_map.insert(key: id, value: tycon)

	pub fn define_variable(is_pub: bool, variable: ast.Variable):
		define(is_pub, name: variable.id.name, kind: ast.SymbolKind.Var(variable), location: variable.location)

	pub fn define_type_parameter(type_parameter: ast.TypeParameter):
		define(is_pub: false, name: type_parameter.id.name, kind: ast.SymbolKind.Typ(ty: ast.type_parameter_ref(type_parameter)), location: type_parameter.location)

	pub fn define_parameter(parameter_def: ast.ParameterDef):
		define(is_pub: false, name: parameter_def.id.name, kind: ast.SymbolKind.Parameter(parameter_def), location: parameter_def.location)

	pub fn define(is_pub: bool, name: str, kind: ast.SymbolKind, location: Location):
		# log_trace("DEFINE {name}")
		let scope = scopes.first()
		if scope.is_defined(name):
			add_error(location, message: "Symbol '{name}' is already defined")
		else:
			scope.define(is_pub, name, kind, location)

	pub fn lookup_expression_kind(name: str, location: Location) -> ast.ExpressionKind except SingleCompilationError:
		let symbol = lookup_base_name(name, location)
		symbol.add_reference(location)
		let introduce_this = if was_class_scope:
			case symbol.kind:
				Function(function_def):
					true
				Var(var_def):
					true
			else:
				false
		else:
			false

		if introduce_this:
			let base = lookup_expression(name: "this", location)
			ast.ExpressionKind.GetAttr(base, field: name)
		else:
			symbol_to_kind(symbol)

	fn lookup_expression(name: str, location: Location) -> ast.Expression except SingleCompilationError:
		let symbol = lookup_base_name(name, location)
		let kind = symbol_to_kind(symbol)
		ast.Expression(kind, ty: ast.undefined_type(), location)

	pub fn resolve_type_kind(name: ast.QualName) -> ast.TypeKind except SingleCompilationError:
		""" Resolve qualified name to a type """
		let symbol = resolve_qual_name(name)
		case symbol.kind:
			Typ(ty):
				ty.kind
			TypeConstructor(tycon):
				ast.TypeKind.UnApp(tycon)
		else:
			raise make_error(location: name.location, message: "Not a type: {symbol}")

	pub fn resolve_tycon(name: ast.QualName) -> ast.TyCon except SingleCompilationError:
		""" Resolve qualified name to a type constructor """
		let symbol = resolve_qual_name(name)
		case symbol.kind:
			TypeConstructor(tycon):
				tycon
		else:
			raise make_error(location: name.location, message: "Not a tycon: {symbol}")

	fn resolve_qual_name(name: ast.QualName) -> ast.Symbol except SingleCompilationError:
		""" Resolve a qualified name to a symbol """
		let base_name = name.parts[0]
		var symbol = lookup_base_name(name: base_name, location: name.location)
		symbol.add_reference(location: name.location)
		if name.parts.len() > 1:
			var first = true
			for part in name.parts:
				if first:
					first = false
					continue
				case symbol.kind:
					Module(module):
						symbol = resolve_attribute(module, attr: part, location: name.location)
				else:
					raise make_error(location: name.location, message: "Not a module we want to get {part} from")

		symbol

	pub fn resolve_attribute(module: ast.ModuleDef, attr: str, location: Location) -> ast.Symbol except SingleCompilationError:
		""" Try to load an attribute from a module. """
		case module.scope.lookup(name: attr):
			Some(symbol):
				if symbol.is_pub:
					symbol
				else:
					raise make_error(location, message: "Symbol '{attr}' is private")
			None:
				raise make_error(location, message: "module '{module.name}' has no symbol: '{attr}'")

	fn lookup_base_name(name: str, location: Location) -> ast.Symbol except SingleCompilationError:
		for scope in scopes:
			case scope.lookup(name):
				Some(symbol):
					was_class_scope = scope.class_scope
					return symbol
				None:
					pass
		raise make_error(location, message: "'{name}' not defined!")

	pub fn enter_scope(scope: ast.Scope):
		scopes.prepend(scope)

	pub fn leave_scope():
		scopes.drop_front()

	fn make_error(location: Location, message: str) -> SingleCompilationError:
		errors.make_error(location, message)

	pub fn add_error(location: Location, message: str):
		errors.add_error(location, message)

	pub fn add_warning(location: Location, message: str):
		errors.add_warning(location, message)

	pub fn render_or_raise() except CompilationError:
		errors.render_or_raise()
