"""
Available transformations:
 - Turn for-loops into while-loops
 - Turn classes into structs with functions
 - Turn enums into tagged unions
 - Turn switch-statement into chain of if-statements

Ideas for transformations:
 - Transform try/except into something else
"""

from location import Location
from utils import panic, log_info, log_debug, assert
from basepass import IdGen
from typechecking import type_check_modules
from listtype import List, list1, list2
from optiontype import Option, option_unwrap, option_is_none, option_is_some
from vectype import vec2, vec3, vec4, Vector, new_vector, new_vector_with_capacity
from hashmap import HashMap, new_hashmap_str
from errors import CompilationError
import ast

pub struct TransformOptions:
	# If the backend can generate code for switch statements, set this boolean to true
	keep_switch: bool

pub fn transform(module_set: ast.ModuleSet, id_gen: IdGen, rt_module: ast.ModuleDef, options: TransformOptions) except CompilationError:
	log_debug("Transforming modules")
	let transformer = Transformer:
		class_rewriter: ClassRewriter(id_gen, rt_module)
		modname: "?"

	let visitor: ast.Visitor[Transformer] = ast.Visitor:
		data: transformer
		on_definition: transformer_on_definition0
		on_type: transformer_on_type0
		on_statement: transformer_on_statement0
		on_expression: transformer_on_expression0
		on_node: transformer_on_node0

	log_debug("Transforming modules 1-a")
	# Phase 1-a:
	# - Rewrite for-loops into while loops
	# - Rewrite loops into while loops
	# - Rewrite ToString contraptions
	# - Rewrite base[x] into base.get(index: x) if base has a 'get' method.
	visitor.on_definition = transformer_on_definition0
	visitor.on_type = transformer_on_type0
	visitor.on_statement = transformer_on_statement1
	visitor.on_expression = transformer_on_expression1
	visitor.on_node = transformer_on_node0
	ast.visit_module_set(visitor, module_set)

	log_debug("Transforming modules 1-b")
	# Phase 1-b:
	# - Rewrite enum definitions into struct definitions
	# - Rewrite classes into structs with functions
	# - Rewrite interface definitions into structs with v-tables.
	visitor.on_definition = transformer_on_definition1
	visitor.on_type = transformer_on_type0
	visitor.on_statement = transformer_on_statement0
	visitor.on_expression = transformer_on_expression0
	visitor.on_node = transformer_on_node0

	for module in module_set.modules:
		ast.visit_module(visitor, module)

		# Filter class-defs / enum-defs / interface-defs:
		let new_defs2: List[ast.Definition] = List()
		for def2 in module.definitions:
			case def2:
				Class(c):
					pass
				Enum(e):
					pass
				Interface(interface_def):
					pass
				Impl(impl_def):
					pass
			else:
				new_defs2.append(def2)

		new_defs2.take_extend(transformer.class_rewriter.new_definitions)
		module.definitions = new_defs2

	# ast.print_ast(module)

	log_debug("Transforming modules 2")
	# Phase 2:
	# - Rewrite call to get-attr into call with base as first argument
	visitor.on_definition = transformer_on_definition0
	visitor.on_type = transformer_on_type0
	visitor.on_statement = transformer_on_statement0
	visitor.on_expression = transformer_on_expression2
	visitor.on_node = transformer_on_node0
	ast.visit_module_set(visitor, module_set)

	log_debug("Transforming modules 3")
	# Phase 3:
	# - Rewrite case statement into switch statement
	# - Rewrite class literal into call to constructor
	# - Rewrite enum literal into struct literal
	visitor.on_definition = transformer_on_definition0
	visitor.on_type = transformer_on_type0
	visitor.on_statement = transformer_on_statement3
	visitor.on_expression = transformer_on_expression3
	visitor.on_node = transformer_on_node0
	ast.visit_module_set(visitor, module_set)

	log_debug("Transforming modules 5")
	# Phase 5:
	# - Change enum types into corresponding struct types
	# - Change class types into corresponding struct types
	# - Rewrite switch statement into chain of if statements
	visitor.on_definition = transformer_on_definition0
	visitor.on_type = transformer_on_type5
	visitor.on_statement = transformer_on_statement5
	visitor.on_expression = transformer_on_expression0
	visitor.on_node = transformer_on_node0
	ast.visit_module_set(visitor, module_set)

	# TBD:
	# Optionally check types in between?
	type_check_modules(module_set, display_warnings: false)

	log_info("Type erasure")

	# Phase 9: remove unions
	visitor.on_definition = transformer_on_definition0
	visitor.on_type = transformer_on_type9
	visitor.on_statement = transformer_on_statement0
	visitor.on_expression = transformer_on_expression9
	visitor.on_node = transformer_on_node0
	ast.visit_module_set(visitor, module_set)
	remove_union_defs(module_set)

	# Phase 7a: apply type erasure (part 1), this involves:
	# - Apply cast to opaque pointer for generic parameters when calling a function
	visitor.on_definition = transformer_on_definition0
	visitor.on_type = transformer_on_type0
	visitor.on_statement = transformer_on_statement7
	visitor.on_expression = transformer_on_expression7
	visitor.on_node = transformer_on_node7
	ast.visit_module_set(visitor, module_set)

	# Phase 7b: apply type erasure (part 2), this involves:
	# - Remove type parameters from structs and functions
	# - Remove type arguments from type applications
	# - Prefix names of definitions with module names
	visitor.on_definition = transformer_on_definition7b
	visitor.on_type = transformer_on_type7
	visitor.on_statement = transformer_on_statement0
	visitor.on_expression = transformer_on_expression0
	visitor.on_node = transformer_on_node7b
	ast.visit_module_set(visitor, module_set)


fn remove_union_defs(module_set: ast.ModuleSet):
	for module in module_set.modules:
		# Filter union-defs:
		let new_defs2: List[ast.Definition] = List()
		for def2 in module.definitions:
			case def2:
				Struct(struct_def):
					if struct_def.is_union:
						pass
					else:
						new_defs2.append(def2)
			else:
				new_defs2.append(def2)

		module.definitions = new_defs2

struct Transformer:
	class_rewriter: ClassRewriter
	modname: str

fn transformer_on_definition0(transformer: Transformer, definition: ast.Definition, phase: ast.VisitPhase):
	pass

fn transformer_on_definition1(transformer: Transformer, definition: ast.Definition, phase: ast.VisitPhase):
	case phase:
		Post:
			case definition:
				Class(class_def):
					transformer.class_rewriter.rewrite_class_def(class_def)
				Enum(enum_def):
					transformer.class_rewriter.rewrite_enum_def(enum_def)
				Interface(interface_def):
					transformer.class_rewriter.rewrite_interface_def(interface_def)
				Impl(impl_def):
					# TODO: this must be called after interfaces have been transformed.
					transformer.class_rewriter.rewrite_impl_def(impl_def)
			else:
				pass
	else:
		pass

fn transformer_on_definition7b(transformer: Transformer, definition: ast.Definition, phase: ast.VisitPhase):
	case phase:
		Post:
			# Remove type parameters. They are all opaque pointers now.
			case definition:
				Struct(struct_def):
					struct_def.type_parameters.clear()
					struct_def.id.name = transformer.modname + "_" + struct_def.id.name
				Function(function_def):
					function_def.type_parameters.clear()
					# Special case for main, to be able to call entry point!
					if function_def.name == "main":
						function_def.name = "main2"
					else:
						function_def.name = transformer.modname + "_" + function_def.name
				Var(var_def):
					var_def.variable.id.name = transformer.modname + "_" + var_def.variable.id.name
			else:
				panic("Only structs and functions supported during type erasure!")
	else:
		pass

fn transformer_on_type0(transformer: Transformer, ty: ast.Type, phase: ast.VisitPhase):
	pass

fn transformer_on_type5(transformer: Transformer, ty: ast.Type, phase: ast.VisitPhase):
	case phase:
		Post:
			case ty.kind:
				App(tycon, type_arguments):
					case tycon:
						Class(class_def):
							let struct_def = transformer.class_rewriter.class_struct_map.get(key: class_def.id)
							ty.kind = ast.TypeKind.App(ast.TyCon.Struct(struct_def), type_arguments)
						Enum(enum_def):
							case transformer.class_rewriter.enum_impl_map.get(key: enum_def.id):
								Struct(struct_def):
									ty.kind = ast.TypeKind.App(ast.TyCon.Struct(struct_def), type_arguments)
								Int:
									ty.kind = ast.int_type().kind
								Nullable:
									ty.kind = ast.opaque_type().kind
						Interface(interface_def):
							let impl2 = transformer.class_rewriter.interface_impl2_map.get(key: interface_def.id)
							ty.kind = ast.TypeKind.App(ast.TyCon.Struct(impl2.struct_def), type_arguments)
					else:
						pass
			else:
				pass
	else:
		pass

fn transformer_on_type7(transformer: Transformer, ty: ast.Type, phase: ast.VisitPhase):
	case phase:
		Post:
			if ty.is_type_parameter():
				ty.change_to(to_type: ast.opaque_type())
			elif ty.is_tycon_app():
				let type_arguments = ty.get_type_arguments()
				type_arguments.clear()
	else:
		pass



fn transformer_on_statement0(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
	pass

fn transformer_on_statement1(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
	case phase:
		Post:
			case statement.kind:
				Loop(loop_statement):
					let condition = ast.bool_literal(value: true, location: statement.location)
					let while_statement = ast.WhileStatement(condition, block: loop_statement.block)
					statement.kind = ast.StatementKind.While(while_statement)
				For(for_statement):
					statement.kind = transformer.class_rewriter.transform_for_loop(for_statement, location: statement.location).kind
				If(if_statement):
					# Constant fold, if constant
					case if_statement.condition.kind:
						BoolLiteral(value):
							log_info("Collapsing if on bool")
							if value:
								# Copy terminator?
								statement.kind = if_statement.true_block.body.kind
							else:
								statement.kind = if_statement.false_block.body.kind
					else:
						pass
			else:
				pass
	else:
		pass

fn transformer_on_statement3(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
	case phase:
		Post:
			case statement.kind:
				Case(case_statement):
					statement.kind = transformer.class_rewriter.transform_case(case_statement).kind
			else:
				pass
	else:
		pass

fn transformer_on_statement5(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
	case phase:
		Post:
			case statement.kind:
				Switch(switch_statement):
					statement.kind = transformer.class_rewriter.transform_switch(switch_statement, location: statement.location)
			else:
				pass
	else:
		pass

fn transformer_on_statement7(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
	case phase:
		Post:
			case statement.kind:
				Assignment(target, op, expr):
					# Check if we must do type erasure:
					transformer.class_rewriter.erase_type(ft: target.ty, value: expr, assign: true)

					# If we cast to a value, we must move the cast to the value side
					case target.kind:
						Unbox(value, to_type):
							if value.ty.is_opaque() or value.ty.is_type_parameter():
								target.change_to(to: value)
							else:
								panic("Only supported type cast from opaque as assignment target (not {value.ty})")
					else:
						pass

			else:
				pass
	else:
		pass

fn transformer_on_expression0(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
	pass

fn transformer_on_expression1(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
	case phase:
		Post:
			case expression.kind:
				ToString(value):
					# Rewrite To String
					# log_info("Rewrite to-string")
					case value.kind:
						IntLiteral(value):
							let new_literal = ast.string_literal(value: str(value), location: expression.location)
							expression.change_to(to: new_literal)
						StringLiteral(value):
							let new_literal = ast.string_literal(value, location: expression.location)
							expression.change_to(to: new_literal)
					else:
						if value.ty.is_str():
							expression.change_to(to: value)
						elif value.ty.is_int():
							# call int-to-str
							let int_to_str_func = transformer.class_rewriter.load_std_function(name: "int_to_str", location: expression.location)
							let arg1 = ast.LabeledExpression(name: Option.Some("value"), value, location: expression.location)
							let arguments = list1(arg1)
							let call = int_to_str_func.call_it(arguments, location: expression.location)
							expression.change_to(to: call)
						elif value.ty.is_char():
							# call char-to-str
							let char_to_str_func = transformer.class_rewriter.load_std_function(name: "char_to_str", location: expression.location)
							let arg1 = ast.LabeledExpression(name: Option.Some("value"), value, location: expression.location)
							let arguments = list1(arg1)
							let call = char_to_str_func.call_it(arguments, location: expression.location)
							expression.change_to(to: call)
						elif value.ty.has_method("to_string"):
							# Invoke to_string method
							let arguments: List[ast.LabeledExpression] = List()
							let call_to_string = value.call_method(method: "to_string", arguments, location: expression.location)
							expression.change_to(to: call_to_string)
						else:
							panic("Invalid type for to-string")
				GetIndex(base, indici):
					if base.ty.has_method("get"):
						assert(condition: indici.len() == 1, message: "Only support single indexing.")
						let index = indici.first()
						let arg1 = ast.LabeledExpression(name: Option.Some("index"), value: index, location: index.location)
						let arguments = list1(arg1)
						let call_get = base.call_method(method: "get", arguments, location: expression.location)
						expression.change_to(to: call_get)
					elif base.ty.is_str():
						assert(condition: indici.len() == 1, message: "Only support single indexing.")
						let index = indici.first()
						let arg1 = ast.LabeledExpression(name: Option.Some("text"), value: base, location: index.location)
						let arg2 = ast.LabeledExpression(name: Option.Some("index"), value: index, location: index.location)
						let arguments = list2(arg1, arg2)
						let str_get_func = transformer.class_rewriter.load_std_function(name: "str_get", location: expression.location)
						let call_str_get = str_get_func.call_it(arguments, location: expression.location)
						expression.change_to(to: call_str_get)
				Binop(binop):
					# Try constant folding
					case binop.lhs.kind:
						IntLiteral(lhs_value):
							case binop.rhs.kind:
								IntLiteral(rhs_value):
									case binop.op:
										Greater:
											log_info("Folding integer greater")
											let value: bool = lhs_value > rhs_value
											let new_literal = ast.bool_literal(value, location: expression.location)
											expression.change_to(to: new_literal)
										Less:
											log_info("Folding integer less")
											let value: bool = lhs_value < rhs_value
											let new_literal = ast.bool_literal(value, location: expression.location)
											expression.change_to(to: new_literal)
										Equals:
											log_info("Folding integer equals")
											let value: bool = lhs_value == rhs_value
											let new_literal = ast.bool_literal(value, location: expression.location)
											expression.change_to(to: new_literal)
										Add:
											log_info("Folding integer add")
											let value = lhs_value + rhs_value
											let new_literal = ast.integer_literal(value, location: expression.location)
											expression.change_to(to: new_literal)
										Sub:
											log_info("Folding integer sub")
											let value = lhs_value - rhs_value
											let new_literal = ast.integer_literal(value, location: expression.location)
											expression.change_to(to: new_literal)
										Mul:
											log_info("Folding integer mul")
											let value = lhs_value * rhs_value
											let new_literal = ast.integer_literal(value, location: expression.location)
											expression.change_to(to: new_literal)
									else:
										pass
							else:
								pass
						StringLiteral(lhs_value):
							case binop.rhs.kind:
								StringLiteral(rhs_value):
									case binop.op:
										Add:
											let value = lhs_value + rhs_value
											let new_literal = ast.string_literal(value, location: expression.location)
											expression.change_to(to: new_literal)
									else:
										pass
							else:
								pass
					else:
						pass
			else:
				pass
	else:
		pass

fn transformer_on_expression2(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
	case phase:
		Post:
			case expression.kind:
				Call(call):
					case call.callee.kind:
						GetAttr(base, name):
							if base.ty.is_class():
								# Rewrite method call
								# log_info("Rewrite method call")
								let function_ref: ast.Expression = ast.get_method_ref_from_type(ty: base.ty, attr: name, location: expression.location)
								let this_arg = ast.LabeledExpression(location: base.location, name: Option.Some("this"), value: base)
								let arguments = call.arguments
								arguments.prepend(this_arg)
								call.callee = function_ref
							elif base.ty.is_interface():
								# Call the invoker function instead
								let interface_def = base.ty.get_interface_def()
								let impl2 = transformer.class_rewriter.interface_impl2_map.get(key: interface_def.id)
								let invoker = impl2.get_invoker(name)
								let type_arguments: Vector[ast.Type] = new_vector()
								let function_ref = ast.function_ref(function_def: invoker, type_arguments, location: expression.location)
								let this_arg = ast.LabeledExpression(location: base.location, name: Option.Some("this"), value: base)
								let arguments = call.arguments
								arguments.prepend(this_arg)
								call.callee = function_ref
					else:
						pass
				Binop(op):
					if op.lhs.ty.is_str():
						case op.op:
							Add:
								# Rewrite adding of strings by calling a runtime str_concat function
								let str_concat_func = transformer.class_rewriter.load_std_function(name: "str_concat", location: expression.location)
								let lhs_arg = ast.LabeledExpression(name: Option.None(), value: op.lhs, location: op.lhs.location)
								let rhs_arg = ast.LabeledExpression(name: Option.None(), value: op.rhs, location: op.rhs.location)
								let arguments = list2(lhs_arg, rhs_arg)
								let call = str_concat_func.call_it(arguments, location: expression.location)
								expression.change_to(to: call)

							Equals:
								# Rewrite '==' for strings into call to runtime function.
								let str_compare_func = transformer.class_rewriter.load_std_function(name: "str_compare", location: expression.location)
								let lhs_arg = ast.LabeledExpression(name: Option.None(), value: op.lhs, location: op.lhs.location)
								let rhs_arg = ast.LabeledExpression(name: Option.None(), value: op.rhs, location: op.rhs.location)
								let arguments = list2(lhs_arg, rhs_arg)
								let call = str_compare_func.call_it(arguments, location: expression.location)
								expression.change_to(to: call)

						else:
							panic("Can only add or compare str types.")
				TypeCast(ty, value):
					if ty.is_interface():
						let new_literal = transformer.class_rewriter.rewrite_cast_to_interface(value, ty)
						expression.change_to(to: new_literal)
			else:
				pass
	else:
		pass

fn transformer_on_expression3(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
	case phase:
		Post:
			case expression.kind:
				ClassLiteral(ty, arguments):
					# Call constructor instead!
					let ctor_call = transformer.class_rewriter.rewrite_class_literal(ty, arguments, location: expression.location)
					expression.change_to(to: ctor_call)
				EnumLiteral(ty, variant, values):
					let struct_literal = transformer.class_rewriter.rewrite_enum_literal(enum_ty: ty, variant, values, location: expression.location)
					expression.change_to(to: struct_literal)
			else:
				pass
	else:
		pass

fn transformer_on_expression7(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
	case phase:
		Post:
			case expression.kind:
				Call(call):
					# Perform type erasure on function call arguments if required.
					let parameter_types = call.callee.ty.get_parameter_types()

					assert(condition: call.arguments.len() == parameter_types.len(), message: "arguments and parameters types must be the same length")
					let ati = call.arguments.iter()
					for pt in parameter_types:
						let argument = option_unwrap(ati.next())
						transformer.class_rewriter.erase_type(ft: pt.ty, value: argument.value, assign: false)

					upcast_type(expression)

				FunctionRef(function_def, type_arguments):
					# Remove type arguments:
					type_arguments.clear()

				StructLiteral(ty, values):
					# Perform type erasure on struct literal values
					let field_types = ty.get_field_types()
					assert(condition: values.len() == field_types.len(), message: "values and field-types must be the same length")
					var index = 0
					for value in values:
						let ft = field_types[index]
						transformer.class_rewriter.erase_type(ft, value, assign: false)
						index += 1

				UnionLiteral(ty, attr, value):
					# Perform type erasure on union literal value
					let ft = ty.get_field_type(attr)
					transformer.class_rewriter.erase_type(ft, value, assign: false)

				GetAttr(base, attr):
					upcast_type(expression)
			else:
				pass
	else:
		pass



fn upcast_type(expression: ast.Expression):
	# Perform type promotion, when this type was a generic
	if expression.ty.was_generic:
		let old_expression = ast.clone_expression(value: expression)
		let new_expression = ast.unbox(value: old_expression, to_type: expression.ty, location: expression.location)
		expression.change_to(to: new_expression)

fn transformer_on_node0(transformer: Transformer, node: ast.VisitNode, phase: ast.VisitPhase):
	pass

fn transformer_on_node7(transformer: Transformer, node: ast.VisitNode, phase: ast.VisitPhase):
	case phase:
		Post:
			case node:
				ModuleNode(module):
					module.definitions.take_extend(transformer.class_rewriter.new_definitions)
			else:
				pass
	else:
		pass

fn transformer_on_node7b(transformer: Transformer, node: ast.VisitNode, phase: ast.VisitPhase):
	case phase:
		Pre:
			case node:
				ModuleNode(module):
					transformer.modname = module.name
			else:
				pass
	else:
		pass

fn transformer_on_type9(transformer: Transformer, ty: ast.Type, phase: ast.VisitPhase):
	# Change unions to opaque pointer types.
	case phase:
		Post:
			if ty.is_union_struct():
				ty.change_to(to_type: ast.opaque_type())
	else:
		pass

fn transformer_on_expression9(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
	case phase:
		Post:
			case expression.kind:
				UnionLiteral(ty, attr, value):
					# Box value
					let boxed_value = ast.box(value, location: expression.location)
					expression.change_to(to: boxed_value)
				GetAttr(base, name):
					if base.ty.is_union_struct():
						# Unbox value
						let to_type = base.ty.get_field_type(attr: name)
						let unboxed_value = ast.unbox(value: base, to_type, location: expression.location)
						expression.change_to(to: unboxed_value)
			else:
				pass
	else:
		pass

enum EnumImpl:
	Int
	Nullable
	Struct(struct_def: ast.StructDef)

class InterfaceImpl2:
	""" Interface implementation details """
	pub var struct_def: ast.StructDef
	var vtable_map: HashMap[str,ast.Variable] = new_hashmap_str()
	var invoker_map: HashMap[str,ast.FunctionDef] = new_hashmap_str()

	pub fn get_impl_vtable(ty: ast.Type) -> ast.Variable:
		""" Get vtable for given type. """
		let key = ty.to_string()
		vtable_map.get(key)

	pub fn set_impl_vtable(ty: ast.Type, vtable: ast.Variable):
		let key = ty.to_string()
		vtable_map.insert(key, value: vtable)

	pub fn set_invoker(name: str, invoker: ast.FunctionDef):
		invoker_map.insert(key: name, value: invoker)

	pub fn get_invoker(name: str) -> ast.FunctionDef:
		invoker_map.get(key: name)

class ClassRewriter:
	var ctor_map: HashMap[ast.NodeId,ast.FunctionDef] = ast.new_hashmap_nodeid()
	pub var class_struct_map: HashMap[ast.NodeId,ast.StructDef] = ast.new_hashmap_nodeid()
	pub var enum_impl_map: HashMap[ast.NodeId,EnumImpl] = ast.new_hashmap_nodeid()
	pub var interface_impl2_map: HashMap[ast.NodeId,InterfaceImpl2] = ast.new_hashmap_nodeid()
	pub var new_definitions: List[ast.Definition] = List()
	var id_gen: IdGen
	var rt_module: ast.ModuleDef

	pub fn rewrite_class_def(class_def: ast.ClassDef):
		log_info("Rewriting class def {class_def.id.name}")
		let methods: List[ast.FunctionDef] = List()
		let builder = ast.StructBuilder()
		builder.set_name(name: class_def.id.name)
		builder.set_id(id: get_unique_id())

		let type_arguments: Vector[ast.Type] = new_vector_with_capacity(capacity: class_def.type_parameters.len())
		for type_parameter in class_def.type_parameters:
			let type_parameter_ref = builder.add_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
			type_arguments.append(type_parameter_ref)
		let m = ast.create_subst_mapping(type_parameters: class_def.type_parameters, type_arguments)

		for definition in class_def.definitions:
			case definition:
				Var(var_def):
					let ty = ast.subst(ty: var_def.variable.ty, m)
					builder.add_field(name: var_def.variable.id.name, ty, location: var_def.variable.location)
				Function(function_def):
					methods.append(function_def)
			else:
				panic("only fields and functions expected, not {ast.definition_to_str(definition)}")

		let struct_def = builder.finish()
		new_definitions.append(ast.Definition.Struct(struct_def))
		class_struct_map.insert(key: class_def.id, value: struct_def)

		# Lift methods:
		for method in methods:
			lift_method(method, class_def, struct_def)

		create_constructor(class_def, struct_def)

	fn lift_method(method: ast.FunctionDef, class_def: ast.ClassDef, struct_def: ast.StructDef):
		let type_arguments: Vector[ast.Type] = new_vector_with_capacity(capacity: class_def.type_parameters.len())
		for type_parameter in class_def.type_parameters:
			type_parameter = ast.new_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
			method.type_parameters.append(type_parameter)
			type_arguments.append(ast.type_parameter_ref(type_parameter))
		let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)
		method.name = "{class_def.id.name}_{method.name}"
		let this_parameter = option_unwrap(method.this_parameter)
		method.this_parameter = Option.None()
		# TODO: why does the below cause trouble?
		# ast.change_type_to(ty: this_parameter.ty, ty2: struct_type)
		method.parameters.prepend(this_parameter)
		new_definitions.append(ast.Definition.Function(method))

	fn create_constructor(class_def: ast.ClassDef, struct_def: ast.StructDef):
		# Create constructor function
		let ctor_name = "{class_def.id.name}_ctor"
		let type_parameters: List[ast.TypeParameter] = List()
		let except_type = ast.void_type()
		let type_arguments: Vector[ast.Type] = new_vector_with_capacity(capacity: class_def.type_parameters.len())
		for type_parameter in class_def.type_parameters:
			type_parameter = ast.new_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
			type_parameters.append(type_parameter)
			type_arguments.append(ast.type_parameter_ref(type_parameter))
		let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)

		let m = ast.create_subst_mapping(type_parameters: class_def.type_parameters, type_arguments)
		let parameters: List[ast.ParameterDef] = List()
		let init_values: List[ast.Expression] = List()
		for definition in class_def.definitions:
			case definition:
				Var(variable_def):
					case variable_def.value:
						Intern(ival):
							case ival:
								Some(iv2):
									init_values.append(iv2)
								None:
									# Create a c-tor parameter
									let ty = ast.subst(ty: variable_def.variable.ty, m)
									let ctor_param = ast.parameter_def(name: variable_def.variable.id.name, id: get_unique_id(), label_is_optional: false, ty, location: class_def.location)
									parameters.append(ctor_param)
									let iv2 = ctor_param.ref(location: class_def.location)
									init_values.append(iv2)
						Extern(libname, initialized):
							if not initialized:
								# Create a c-tor parameter
								let ty = ast.subst(ty: variable_def.variable.ty, m)
								let ctor_param = ast.parameter_def(name: variable_def.variable.id.name, id: get_unique_id(), label_is_optional: false, ty, location: class_def.location)
								parameters.append(ctor_param)
			else:
				pass

		let libname = "?"
		let docstring: Option[str] = Option.None()
		var ctor_func = ast.extern_function_def(is_pub: true, libname, name: ctor_name, docstring, type_parameters, parameters, return_type: struct_type, location: class_def.location)
		case class_def.is_extern:
			Some(libname):
				ctor_func = ast.extern_function_def(is_pub: true, libname, name: ctor_name, docstring, type_parameters, parameters, return_type: struct_type, location: class_def.location)
			None:
				let init_literal = ast.struct_literal(ty: struct_type, values: init_values, location: class_def.location)
				let body = ast.return_statement(value: Option.Some(init_literal), location: class_def.location)
				ctor_func = ast.function_def(is_pub: true, name: ctor_name, docstring: Option.None(), type_parameters, this_parameter: Option.None(), parameters, return_type: struct_type, except_type, body, location: class_def.location)

		# Use node-id to store constructor:
		ctor_map.insert(key: class_def.id, value: ctor_func)
		new_definitions.append(ast.Definition.Function(ctor_func))

	pub fn rewrite_class_literal(ty: ast.Type, arguments: List[ast.LabeledExpression], location: Location) -> ast.Expression:
		let class_def = ty.get_class_def()
		let ctor_func_def: ast.FunctionDef = case ctor_map.maybe_get(key: class_def.id):
			Some(value):
				value
			None:
				panic("Ctor not found: {class_def.id.name}")
		let type_arguments = ty.get_type_arguments()
		let ctor_func_ref = ast.function_ref(function_def: ctor_func_def, type_arguments, location)
		let struct_ty: ast.Type = ast.undefined_type()
		ast.call(callee: ctor_func_ref, arguments, ty: struct_ty, location)

	fn get_unique_id() -> int:
		id_gen.new_id()

	fn new_variable(name: str, ty: ast.Type, location: Location) -> ast.Variable:
		# Create a new variable with unique id
		let id = get_unique_id()
		ast.variable(name, id, ty, location)

	fn get_enum_impl(id: ast.NodeId) -> EnumImpl:
		enum_impl_map.get(key: id)

	pub fn load_std_function(name: str, location: Location) -> ast.Expression:
		# Get expression that loads a builtin runtime function.
		let symbol = option_unwrap(rt_module.scope.lookup(name))
		case symbol.kind:
			Function(function_def):
				let type_arguments: Vector[ast.Type] = new_vector()
				ast.function_ref(function_def, type_arguments, location)
		else:
			panic("{name} must be external function")

	pub fn rewrite_interface_def(interface_def: ast.InterfaceDef):
		# Create method table for this interface
		log_debug("Rewrite interface def {interface_def.id.name}")
		let builder1 = ast.StructBuilder()
		builder1.set_name(name: "{interface_def.id.name}Functions")
		builder1.set_id(id: get_unique_id())

		let type_arguments: Vector[ast.Type] = new_vector_with_capacity(capacity: interface_def.type_parameters.len())
		for type_parameter in interface_def.type_parameters:
			let type_parameter_ref = builder1.add_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
			type_arguments.append(type_parameter_ref)
		let m = ast.create_subst_mapping(type_parameters: interface_def.type_parameters, type_arguments)

		for definition in interface_def.definitions:
			case definition:
				Function(function_def):
					let type_arguments: Vector[ast.Type] = new_vector()
					uplift_this_parameter(function_def)
					let ty = ast.get_function_type2(function_def, type_arguments)
					builder1.add_field(name: function_def.name, ty, location: interface_def.location)
			else:
				panic("only functions expected, not {ast.definition_to_str(definition)}")

		let struct_def1 = builder1.finish()
		new_definitions.append(ast.Definition.Struct(struct_def1))

		log_debug("Creating struct for {interface_def.id.name}")
		let builder2 = ast.StructBuilder()
		builder2.set_name(name: "{interface_def.id.name}Combo")
		builder2.set_id(id: get_unique_id())
		builder2.add_field(name: "data", ty: ast.opaque_type(), location: interface_def.location)
		let type_arguments2: Vector[ast.Type] = new_vector()
		let vtable_ty = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def1), type_arguments: type_arguments2)
		builder2.add_field(name: "vtable", ty: vtable_ty, location: interface_def.location)
		let struct_def2 = builder2.finish()
		new_definitions.append(ast.Definition.Struct(struct_def2))
		let impl2 = InterfaceImpl2(struct_def: struct_def2)
		interface_impl2_map.insert(key: interface_def.id, value: impl2)

		let type_arguments3: Vector[ast.Type] = new_vector()
		let this_ty = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def2), type_arguments: type_arguments3)

		# Create invoker functions
		for definition in interface_def.definitions:
			case definition:
				Function(function_def):
					let invoke_helper = create_invoker_helper(this_ty, function_def)
					impl2.set_invoker(name: function_def.name, invoker: invoke_helper)
					new_definitions.append(ast.Definition.Function(invoke_helper))
			else:
				panic("only functions expected, not {ast.definition_to_str(definition)}")

	fn create_invoker_helper(this_ty: ast.Type, function_def: ast.FunctionDef) -> ast.FunctionDef:
		""" Create a function that takes a vtable/data pair, which calls the proper function. """
		let location = function_def.location
		let type_parameters: List[ast.TypeParameter] = List() # TODO
		let parameters: List[ast.ParameterDef] = List()
		# let this_param = ast.parameter_def:
		# 	name: "this"
		# 	id: get_unique_id()
		# 	label_is_optional: false
		# 	ty: this_ty
		# 	location: function_def.location
		# parameters.append(this_param)
		for p in function_def.parameters:
			parameters.append(p)
		let this_param = parameters[0]
		this_param.ty = this_ty

		let target = this_param.ref(location).get_attr_typed(attr: "vtable", location).get_attr_typed(attr: function_def.name, location)
		let arguments: List[ast.LabeledExpression] = List()
		var first = true
		for parameter in parameters:
			if first:
				let data = this_param.ref(location).get_attr_typed(attr: "data", location)
				arguments.append(ast.LabeledExpression(location, name: Option.Some("this"), value: data))
				first = false
			else:
				let data = parameter.ref(location)
				let argument_label = parameter.id.name
				arguments.append(ast.LabeledExpression(location, name: Option.Some(argument_label), value: data))
		let type_arguments: Vector[ast.Type] = new_vector()
		let ftype = ast.get_function_type2(function_def, type_arguments)
		let return_type = ftype.get_return_type()
		let except_type = ftype.get_except_type()
		let call_expr = ast.call(callee: target, arguments, ty: return_type, location)
		let body = ast.expression_statement(expr: call_expr)

		# parameters.append(ast.ParameterDef())
		let invoker_function_def = ast.function_def:
			is_pub: true
			name: "invoke_{function_def.name}"
			docstring: Option.None()
			type_parameters
			this_parameter: Option.None()
			parameters
			return_type
			except_type
			body
			location: function_def.location
		invoker_function_def

	pub fn rewrite_impl_def(impl_def: ast.ImplDef):
		""" Create a global variable initialized with a vtable.

		Move implementing function to toplevel
		"""
		log_debug("Rewrite interface implementation")

		let values: List[ast.Expression] = List()
		let type_key = impl_def.target_type.to_string()
		for definition in impl_def.definitions:
			case definition:
				Function(method):
					# TODO: merge code with the lift_method function?
					method.name = "{impl_def.id.name}_{method.name}"
					uplift_this_parameter(function_def: method)
					new_definitions.append(ast.Definition.Function(method))

					let wrapper_function = create_impl_wrapper_func(method)

					let type_arguments: Vector[ast.Type] = new_vector()
					values.append(ast.function_ref(function_def: wrapper_function, type_arguments, location: impl_def.location))
			else:
				panic("Only functions expected")

		let interface_def = impl_def.interface_type.get_interface_def()
		let impl2 = interface_impl2_map.get(key: interface_def.id)

		let type_arguments2: Vector[ast.Type] = new_vector()
		let iface_type = ast.apply_tycon(tycon: ast.TyCon.Struct(impl2.struct_def), type_arguments: type_arguments2)

		let vtable_ty = iface_type.get_field_type(attr: "vtable")
		let vtable_value = ast.struct_literal(ty: vtable_ty, values, location: impl_def.location)
		let variable = ast.variable(name: "vtable", id: get_unique_id(), ty: vtable_ty, location: impl_def.location)
		impl2.set_impl_vtable(ty: impl_def.target_type, vtable: variable)
		let vtable_global = ast.VariableDef(is_pub: true, variable, value: ast.VariableDefValue.Intern(value: Option.Some(vtable_value)))
		new_definitions.append(ast.Definition.Var(vtable_global))

	fn create_impl_wrapper_func(method: ast.FunctionDef) -> ast.FunctionDef:
		# Introduce a wrapper function to unbox the this parameter into the right type.
		let location = method.location
		let type_parameters: List[ast.TypeParameter] = List() # TODO
		let parameters: List[ast.ParameterDef] = List()
		let arguments: List[ast.LabeledExpression] = List()
		let this_param: ast.ParameterDef = ast.parameter_def:
			name: "this"
			id: get_unique_id()
			label_is_optional: true
			ty: ast.opaque_type()
			location

		parameters.append(this_param)
		let this_unboxed = ast.unbox:
			value: this_param.ref(location)
			to_type: method.parameters.get(index: 0).ty
			location
		arguments.append(ast.LabeledExpression(location, name: Option.Some("this"), value: this_unboxed))

		var first = true
		for p in method.parameters:
			if first:
				first = false
			else:
				let p2: ast.ParameterDef = ast.parameter_def:
					name: p.id.name
					id: get_unique_id()
					label_is_optional: true
					ty: p.ty
					location
				parameters.append(p2)
				arguments.append(ast.LabeledExpression(location, name: Option.Some(p.id.name), value: p2.ref(location)))

		let type_arguments: Vector[ast.Type] = new_vector()
		let method_ref = ast.function_ref(function_def: method, type_arguments, location)
		let call_impl = ast.call(callee: method_ref, arguments, ty: ast.void_type(), location)
		let wrapper_function = ast.function_def:
			is_pub: true
			name: "{method.name}_wrapper"
			docstring: Option.None()
			type_parameters
			this_parameter: Option.None()
			parameters
			return_type: method.info.return_type
			except_type: method.info.except_type
			body: ast.expression_statement(expr: call_impl)
			location: method.location
		new_definitions.append(ast.Definition.Function(wrapper_function))
		wrapper_function

	pub fn rewrite_cast_to_interface(value: ast.Expression, ty: ast.Type) -> ast.Expression:
		""" Turn cast to interface into struct literal with data + vtable """
		let interface_def = ty.get_interface_def()
		let impl2 = interface_impl2_map.get(key: interface_def.id)
		let type_arguments2: Vector[ast.Type] = new_vector()
		let iface_type = ast.apply_tycon(tycon: ast.TyCon.Struct(impl2.struct_def), type_arguments: type_arguments2)
		let vtable_global_var = impl2.get_impl_vtable(ty: value.ty)
		let vtable_ptr = vtable_global_var.ref(location: value.location)
		let data_ptr = ast.box(value, location: value.location)
		let values: List[ast.Expression] = list2(data_ptr, vtable_ptr)
		ast.struct_literal(ty: iface_type, values, location: value.location)

	pub fn transform_for_loop(for_statement: ast.ForStatement, location: Location) -> ast.Statement:
		""" Turn for loop into iterator and while loop """
		log_debug("Rewrite for loop")

		if for_statement.iter_value.ty.is_array():
			transform_for_loop_over_array(for_statement, location)
		elif for_statement.iter_value.ty.is_iterable_like():
			transform_for_loop_over_iterator(for_statement, location)
		elif for_statement.iter_value.ty.is_sequence_like():
			transform_for_loop_over_sequence(for_statement, location)
		elif for_statement.iter_value.ty.is_str():
			transform_for_loop_over_str(for_statement, location)
		else:
			panic("Cannot for-loop over {for_statement.iter_value.ty}")

	fn transform_for_loop_over_iterator(for_statement: ast.ForStatement, location: Location) -> ast.Statement:
		# Implement loop over 'iter' method:
		# log_info(".... {for_statement.iter_value.ty}")
		var arguments: List[ast.LabeledExpression] = List()
		let iter_val = for_statement.iter_value.call_method(method: "iter", arguments, location)
		let iter_var = new_variable(name: "it", ty: iter_val.ty, location)
		let let_it_var = ast.let_statement(variable: iter_var, type_hint: Option.None(), value: iter_val, location)

		# log_info("....>>> {iter_var.ty}")
		arguments = List()
		let opt_val = iter_var.ref(location).call_method(method: "next", arguments, location)
		let opt_var = new_variable(name: "opt", ty: opt_val.ty, location)
		let let_opt_var = ast.let_statement(variable: opt_var, type_hint: Option.None(), value: opt_val, location)

		let arm1 = ast.CaseArm:
			location
			name: "None"
			variables: List()
			block: ast.scoped_block(body: ast.break_statement(location))
		let arm2 = ast.CaseArm:
			location
			name: "Some"
			variables: list1(for_statement.iter_var)
			block: for_statement.block
		let arms: List[ast.CaseArm] = list2(arm1, arm2)

		let case_statement = ast.case_statement(value: opt_var.ref(location), arms, else_clause: Option.None(), location)
		let true_value = ast.bool_literal(value: true, location)
		let loop_body = ast.compound(inner: vec2(let_opt_var, case_statement), location)
		let loop_statement = ast.while_statement(condition: true_value, body: loop_body, location)

		ast.compound(inner: vec2(let_it_var, loop_statement), location)

	fn transform_for_loop_over_sequence(for_statement: ast.ForStatement, location: Location) -> ast.Statement:
		let sequence_type = for_statement.iter_value.ty

		# let x = iter_value
		let x_var = new_variable(name: "x", ty: sequence_type, location)
		let let_x = ast.let_statement(variable: x_var, type_hint: Option.None(), value: for_statement.iter_value, location)

		# let index = 0
		let index_var = new_variable(name: "index", ty: ast.int_type(), location)
		index_var.writable = true
		let zero = ast.integer_literal(value: 0, location)
		let let_index = ast.let_statement(variable: index_var, type_hint: Option.None(), value: zero, location)

		# let size = x.len()
		let size_var = new_variable(name: "size", ty: ast.int_type(), location)
		let x_ref1 = x_var.ref(location)
		let method_arguments_for_len: List[ast.LabeledExpression] = List()
		let call_len_method = x_ref1.call_method(method: "len", arguments: method_arguments_for_len, location)
		let let_size = ast.let_statement(variable: size_var, type_hint: Option.None(), value: call_len_method, location)

		# index < size
		let index_ref1 = index_var.ref(location)
		let size_ref1 = size_var.ref(location)
		let condition = ast.binop(lhs: index_ref1, op: ast.BinaryOperator.Less(), rhs: size_ref1, ty: ast.bool_type(), location)

		# v = x.get(index)
		let x_ref2 = x_var.ref(location)
		let index_ref2 = index_var.ref(location)
		let method_arguments_for_get: List[ast.LabeledExpression] = List()
		method_arguments_for_get.append(ast.LabeledExpression(name: Option.Some("index"), value: index_ref2, location))
		let call_get_method = x_ref2.call_method(method: "get", arguments: method_arguments_for_get, location)
		let let_v = ast.let_statement(variable: for_statement.iter_var, type_hint: Option.None(), value: call_get_method, location)

		# index = index + 1
		let index_ref3 = index_var.ref(location)
		let index_ref4 = index_var.ref(location)
		let one = ast.integer_literal(value: 1, location)
		let index_plus_1 = index_ref4.add(rhs: one, location)
		let inc_index = ast.assignment_statement(target: index_ref3, op: Option.None(), value: index_plus_1, location)

		# While loop:
		let loop_body1 = ast.compound(inner: vec3(let_v, inc_index, for_statement.block.body), location)
		let while_loop = ast.while_statement(condition, body: loop_body1, location)

		ast.compound(inner: vec4(let_x, let_index, let_size, while_loop), location)

	fn transform_for_loop_over_array(for_statement: ast.ForStatement, location: Location) -> ast.Statement:
		# Turn for loop into index / while loop
		let array_type = for_statement.iter_value.ty

		# let arr = iter_value
		let x_var = new_variable(name: "x", ty: array_type, location)
		let let_x = ast.let_statement(variable: x_var, type_hint: Option.None(), value: for_statement.iter_value, location)

		# index = 0
		let index_var = new_variable(name: "index", ty: ast.int_type(), location)
		index_var.writable = true
		let zero = ast.integer_literal(value: 0, location)
		let let_index = ast.let_statement(variable: index_var, type_hint: Option.None(), value: zero, location)

		# index < len(array)
		let array_size = ast.integer_literal(value: array_type.get_array_size(), location)
		let index_ref1 = index_var.ref(location)
		let condition = ast.binop(lhs: index_ref1, op: ast.BinaryOperator.Less(), rhs: array_size, ty: ast.bool_type(), location)

		# v = x[index]
		let x_ref1 = x_var.ref(location)
		let index_ref2 = index_var.ref(location)
		let x_indexed = ast.subscript(base: x_ref1, indici: list1(index_ref2), ty: array_type.get_element_type(), location)
		let let_v = ast.let_statement(variable: for_statement.iter_var, type_hint: Option.None(), value: x_indexed, location)

		# index = index + 1
		let index_ref3 = index_var.ref(location)
		let index_ref4 = index_var.ref(location)
		let one = ast.integer_literal(value: 1, location)
		let index_plus_1 = index_ref4.add(rhs: one, location)
		let inc_index = ast.assignment_statement(target: index_ref3, op: Option.None(), value: index_plus_1, location)

		# While loop:
		let loop_body1 = ast.compound(inner: vec3(let_v, inc_index, for_statement.block.body), location)
		let while_loop = ast.while_statement(condition, body: loop_body1, location)

		ast.compound(inner: vec3(let_x, let_index, while_loop), location)

	fn transform_for_loop_over_str(for_statement: ast.ForStatement, location: Location) -> ast.Statement:
		let str_type = for_statement.iter_value.ty

		# let x = iter_value
		let x_var = new_variable(name: "x", ty: str_type, location)
		let let_x = ast.let_statement(variable: x_var, type_hint: Option.None(), value: for_statement.iter_value, location)

		# let index = 0
		let index_var = new_variable(name: "index", ty: ast.int_type(), location)
		index_var.writable = true
		let zero = ast.integer_literal(value: 0, location)
		let let_index = ast.let_statement(variable: index_var, type_hint: Option.None(), value: zero, location)

		# let size = str_len(text: x)
		let size_var = new_variable(name: "size", ty: ast.int_type(), location)
		let str_len_func = load_std_function(name: "str_len", location)
		let x_ref1 = x_var.ref(location)
		let arguments_for_str_len: List[ast.LabeledExpression] = List()
		arguments_for_str_len.append(ast.LabeledExpression(name: Option.Some("text"), value: x_ref1, location))
		let call_str_len = str_len_func.call_it(arguments: arguments_for_str_len, location)
		let let_size = ast.let_statement(variable: size_var, type_hint: Option.None(), value: call_str_len, location)

		# index < size
		let index_ref1 = index_var.ref(location)
		let size_ref1 = size_var.ref(location)
		let condition = ast.binop(lhs: index_ref1, op: ast.BinaryOperator.Less(), rhs: size_ref1, ty: ast.bool_type(), location)

		# v = str_get(text: x, index: index)
		let str_get_func = load_std_function(name: "str_get", location)
		let x_ref2 = x_var.ref(location)
		let index_ref2 = index_var.ref(location)
		let arguments_for_str_get: List[ast.LabeledExpression] = List()
		arguments_for_str_get.append(ast.LabeledExpression(name: Option.Some("text"), value: x_ref2, location))
		arguments_for_str_get.append(ast.LabeledExpression(name: Option.Some("index"), value: index_ref2, location))
		let call_str_get = str_get_func.call_it(arguments: arguments_for_str_get, location)
		let let_v = ast.let_statement(variable: for_statement.iter_var, type_hint: Option.None(), value: call_str_get, location)

		# index = index + 1
		let index_ref3 = index_var.ref(location)
		let index_ref4 = index_var.ref(location)
		let one = ast.integer_literal(value: 1, location)
		let index_plus_1 = index_ref4.add(rhs: one, location)
		let inc_index = ast.assignment_statement(target: index_ref3, op: Option.None(), value: index_plus_1, location)

		# While loop:
		let loop_body1 = ast.compound(inner: vec3(let_v, inc_index, for_statement.block.body), location)
		let while_loop = ast.while_statement(condition, body: loop_body1, location)

		ast.compound(inner: vec4(let_x, let_index, let_size, while_loop), location)

	pub fn transform_switch(switch_statement: ast.SwitchStatement, location: Location) -> ast.StatementKind:
		# Turn switch into sequence of if-else
		let x_var = new_variable(name: "x", ty: ast.int_type(), location)
		let let_x = ast.let_statement(variable: x_var, type_hint: Option.None(), value: switch_statement.value, location)

		var else_clause = switch_statement.default_block.body
		for arm in switch_statement.arms:
			let x_ref = x_var.ref(location: arm.location)
			let eq_op = ast.BinaryOperator.Equals()
			let eq_ty = ast.bool_type()
			let condition = ast.binop(lhs: x_ref, op: eq_op, rhs: arm.value, ty: eq_ty, location: arm.location)
			else_clause = ast.if_statement(condition, body: arm.block.body, false_body: else_clause, location: arm.location)

		ast.StatementKind.Compound(vec2(let_x, else_clause))

	pub fn rewrite_enum_def(enum_def: ast.EnumDef):
		log_info("Rewriting enum def {enum_def.id.name}")

		# Check for enum def characteristics:
		var n_arms = 0
		var n_payload_arms = 0
		var n_nullable_arms = 0
		for variant in enum_def.variants:
			n_arms += 1
			if variant.payload.len() > 0:
				n_payload_arms += 1
				if variant.payload.len() == 1 and variant.payload.first().is_nullable():
					n_nullable_arms += 1

		if n_payload_arms == 0:
			# A simple tag suffices!
			enum_impl_map.insert(key: enum_def.id, value: EnumImpl.Int())
		elif n_arms == 2 and n_payload_arms == 1 and n_nullable_arms == 1:
			# We can check if the value is null or not
			enum_impl_map.insert(key: enum_def.id, value: EnumImpl.Nullable())
		else:
			# The general case:
			# use a struct with 'tag' and 'data' fields

			let builder2 = ast.StructBuilder()
			builder2.set_name(name: "{enum_def.id.name}Data")
			builder2.set_id(get_unique_id())
			builder2.set_is_union(true)

			let type_arguments2: Vector[ast.Type] = new_vector_with_capacity(capacity: enum_def.type_parameters.len())
			for type_parameter in enum_def.type_parameters:
				let type_parameter_ref2 = builder2.add_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
				type_arguments2.append(type_parameter_ref2)

			for variant in enum_def.variants:
				let union_field_name = "data_{variant.name}"
				if variant.payload.len() == 1:
					let t3 = variant.payload.first()
					builder2.add_field(name: union_field_name, ty: t3, location: variant.location)
				elif variant.payload.len() > 1:
					let builder3 = ast.StructBuilder()
					builder3.set_name(name: "{enum_def.id.name}Data{variant.name}")
					builder3.set_id(id: get_unique_id())

					var idx = 0
					for payload_type in variant.payload:
						builder3.add_field(name: "f_{idx}", ty: payload_type, location: variant.location)
						idx += 1

					let struct_def3 = builder3.finish()
					new_definitions.append(ast.Definition.Struct(struct_def3))
					let t3 = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def3), type_arguments: type_arguments2)
					builder2.add_field(name: union_field_name, ty: t3, location: variant.location)

			# Add field for enum variants without data:
			builder2.add_field(name: "nodata", ty: ast.opaque_type(), location: enum_def.location)

			let union_def = builder2.finish()
			new_definitions.append(ast.Definition.Struct(union_def))

			let builder = ast.StructBuilder()
			builder.set_name(name: enum_def.id.name)
			builder.set_id(get_unique_id())

			let type_arguments: Vector[ast.Type] = new_vector_with_capacity(capacity: enum_def.type_parameters.len())
			for type_parameter in enum_def.type_parameters:
				let type_parameter_ref = builder.add_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
				type_arguments.append(type_parameter_ref)

			builder.add_field(name: "tag", ty: ast.int_type(), location: enum_def.location)
			let union_type = ast.apply_tycon(tycon: ast.TyCon.Struct(union_def), type_arguments)
			builder.add_field(name: "data", ty: union_type, location: enum_def.location)
			let struct_def = builder.finish()
			# let m = ast.create_subst_mapping(type_parameters: enum_def.type_parameters, type_arguments)

			new_definitions.append(ast.Definition.Struct(struct_def))
			enum_impl_map.insert(key: enum_def.id, value: EnumImpl.Struct(struct_def))

	pub fn transform_case(case_statement: ast.CaseStatement) -> ast.Statement:
		""" Transform case statement into switch case over tag values. """
		let location = case_statement.value.location
		let enum_def = case_statement.value.ty.get_enum_def()
		case get_enum_impl(id: enum_def.id):
			Struct(struct_def):
				let type_arguments = case_statement.value.ty.get_type_arguments()
				let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)

				let x_var = new_variable(name: "x", ty: struct_type, location)
				let store_tagged_union = ast.let_statement(variable: x_var, type_hint: Option.None(), value: case_statement.value, location)

				let switch_arms: List[ast.SwitchArm] = List()
				for arm in case_statement.arms:
					let variant = option_unwrap(ast.get_enum_variant(enum_def, attr: arm.name))
					let arm_tag = variant.tag_value
					let union_field_name = "data_{variant.name}"
					let switch_arm_value = ast.integer_literal(value: arm_tag, location: arm.location)
					let switch_arm_body: Vector[ast.Statement] = new_vector()

					# Unpack payload:
					if arm.variables.len() == 1:
						let x_var_ref = x_var.ref(location: arm.location)
						let data_value = x_var_ref.get_attr_typed(attr: "data", location: arm.location)
						let union_value = data_value.get_attr_typed(attr: union_field_name, location: arm.location)
						let store_var = ast.let_statement(variable: arm.variables.first(), type_hint: Option.None(), value: union_value, location: arm.location)
						switch_arm_body.append(store_var)
					elif arm.variables.len() > 1:
						var idx = 0
						for variable in arm.variables:
							let x_var_ref = x_var.ref(location: arm.location)
							let data_value = x_var_ref.get_attr_typed(attr: "data", location: arm.location)
							let union_value = data_value.get_attr_typed(attr: union_field_name, location: arm.location)
							let actual_value = union_value.get_attr_typed(attr: "f_{idx}", location: arm.location)
							let store_var = ast.let_statement(variable, type_hint: Option.None(), value: actual_value, location: arm.location)
							switch_arm_body.append(store_var)
							idx += 1

					switch_arm_body.append(arm.block.body)
					let switch_arm = ast.SwitchArm:
						location: arm.location
						value: switch_arm_value
						block: ast.scoped_block(body: ast.compound(inner: switch_arm_body, location: arm.location))
					switch_arms.append(switch_arm)

				let switch_default_code: ast.Statement = case case_statement.else_block:
					None:
						ast.unreachable_statement(location)
					Some(else_block):
						else_block.body

				let x_var_ref0 = x_var.ref(location)
				let switch_value = x_var_ref0.get_attr_typed(attr: "tag", location)
				let switch_on_tag = ast.switch_statement(value: switch_value, arms: switch_arms, default_body: switch_default_code, location)

				ast.compound(inner: vec2(store_tagged_union, switch_on_tag), location)
			Nullable:
				# Change case to if-null construction
				let x_var = new_variable(name: "x", ty: ast.opaque_type(), location)
				let store_nullable = ast.let_statement(variable: x_var, type_hint: Option.None(), value: case_statement.value, location)

				# Determine true and false arms
				var optional_true_body: Option[ast.Statement] = Option.None()
				var optional_false_body: Option[ast.Statement] = Option.None()

				for arm in case_statement.arms:
					let variant = option_unwrap(ast.get_enum_variant(enum_def, attr: arm.name))
					let is_null_case = variant.payload.len() == 0
					if is_null_case:
						optional_true_body = Option.Some(arm.block.body)
					else:
						assert(condition: variant.payload.len() == 1, message: "Number of payload items must be one.")
						# Unpack payload:
						let x_var_ref1 = x_var.ref(location: arm.location)
						let payload_types = ast.get_variant_payload_types(ty: case_statement.value.ty, variant)
						assert(condition: payload_types.len() == 1, message: "number of types must be 1")
						let to_type = payload_types.first()
						let value = ast.unbox(value: x_var_ref1, to_type, location: arm.location)
						let store_var = ast.let_statement(variable: arm.variables.first(), type_hint: Option.None(), value, location: arm.location)

						optional_false_body = Option.Some(ast.compound(inner: vec2(store_var, arm.block.body), location: arm.location))

				case case_statement.else_block:
					None:
						# When no default case is given, all paths must be covered
						assert(condition: option_is_some(optional_true_body) and option_is_some(optional_false_body), message: "Both paths must be covered")
					Some(else_block):
						if option_is_none(optional_true_body):
							optional_true_body = Option.Some(else_block.body)
						elif option_is_none(optional_false_body):
							optional_false_body = Option.Some(else_block.body)

				# Both if-arms must be covered
				let true_body = option_unwrap(optional_true_body)
				let false_body = option_unwrap(optional_false_body)

				# if x == null
				let x_var_ref0 = x_var.ref(location)
				let null_test_value = ast.null_value(location)
				let condition = x_var_ref0.equals(rhs: null_test_value, location)
				let choice = ast.if_statement(condition, body: true_body, false_body, location)

				ast.compound(inner: vec2(store_nullable, choice), location)
			Int:
				let switch_arms: List[ast.SwitchArm] = List()
				for arm in case_statement.arms:
					let variant = option_unwrap(ast.get_enum_variant(enum_def, attr: arm.name))
					let arm_tag = variant.tag_value
					let switch_arm_value = ast.integer_literal(value: arm_tag, location: arm.location)
					let switch_arm_body = arm.block.body
					let switch_arm = ast.SwitchArm:
						location: arm.location
						value: switch_arm_value
						block: ast.scoped_block(body: switch_arm_body)
					switch_arms.append(switch_arm)

				let switch_default_code: ast.Statement = case case_statement.else_block:
					None:
						ast.unreachable_statement(location)
					Some(else_block):
						else_block.body

				ast.switch_statement(value: case_statement.value, arms: switch_arms, default_body: switch_default_code, location)

	pub fn rewrite_enum_literal(enum_ty: ast.Type, variant: ast.EnumVariant, values: List[ast.Expression], location: Location) -> ast.Expression:
		# log_info("Rewrite enum literal")
		let enum_def = enum_ty.get_enum_def()
		let tag_value = variant.tag_value
		let tag = ast.integer_literal(value: tag_value, location)
		case get_enum_impl(id: enum_def.id):
			Int:
				tag
			Nullable:
				if values.len() == 0:
					ast.null_value(location)
				elif values.len() == 1:
					ast.box(value: values.first(), location)
				else:
					panic("Bad nullable")
			Struct(struct_def):
				let type_arguments = enum_ty.get_type_arguments()
				let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)
				let union_type = struct_type.get_field_type(attr: "data")

				var union_field_name = "data_{variant.name}"
				let union_value = if values.len() == 0:
					union_field_name = "nodata"
					ast.null_value(location)
				elif values.len() == 1:
					values.first()
				else:
					let struct_type2 = union_type.get_field_type(attr: union_field_name)
					ast.struct_literal(ty: struct_type2, values, location)
				let data = ast.union_literal(ty: union_type, field: union_field_name, value: union_value, location)
				ast.struct_literal(ty: struct_type, values: list2(tag, data), location)

	pub fn erase_type(ft: ast.Type, value: ast.Expression, assign: bool):
		if ft.was_generic and not assign:
			let old_value = ast.clone_expression(value)
			let new_value = ast.box(value: old_value, location: value.location)
			value.change_to(to: new_value)
		elif ft.is_function_type():
			let parameter_types = ast.get_types_from_parameter_types(ft.get_parameter_types())
			let return_type = ft.get_return_type()

			# Check if we need a bridge function:
			var opaq = false
			for pt in parameter_types:
				if needs_opaque_cast(pt):
					opaq = true
			if needs_opaque_cast(return_type):
				opaq = true

			if opaq:
				log_info("We need a bridge function for {ft} {value}")
				case value.kind:
					FunctionRef(function_def, type_arguments):
						# TODO: check for existing bridge functions!
						let bridge_function = create_bridge_function(function_def, parameter_types, return_type)
						value.kind = ast.ExpressionKind.FunctionRef(bridge_function, type_arguments: new_vector())
				else:
					panic("Can only bridge a function reference")

	fn create_bridge_function(function_def: ast.FunctionDef, parameter_types: Vector[ast.Type], return_type: ast.Type) -> ast.FunctionDef:
		# Create a bridge function which takes potential opaque parameters
		# and calls the specific function with opaque types casted.
		let location = function_def.location
		let bridge_function_name = "X{get_unique_id()}_bridge_to_{function_def.name}"
		let type_parameters: List[ast.TypeParameter] = List()
		let parameters: List[ast.ParameterDef] = List()
		let arguments: List[ast.LabeledExpression] = List()
		var return_type2 = function_def.info.return_type
		assert(condition: function_def.info.except_type.is_void(), message: "Bridge function only supports non-throwing functions")
		let except_type = ast.void_type()
		var index = 0
		for parameter in function_def.parameters:
			let pt = parameter_types[index]
			index += 1
			let needs_cast = needs_opaque_cast(pt)

			let ty = if needs_cast:
				ast.opaque_type()
			else:
				parameter.ty
			let bridge_function_parameter = ast.parameter_def(name: parameter.id.name, id: get_unique_id(), label_is_optional: true, ty, location)
			parameters.append(bridge_function_parameter)

			let parameter_ref = bridge_function_parameter.ref(location)
			let argument = ast.LabeledExpression(name: Option.Some(parameter.id.name), value: parameter_ref, location)
			if needs_cast:
				# Introduce cast from opaque to specific type here.
				argument.value = ast.unbox(value: argument.value, to_type: parameter.ty, location)
			arguments.append(argument)

		let function_ref = ast.function_ref(function_def, type_arguments: new_vector(), location)
		let function_call = ast.call(callee: function_ref, arguments, ty: ast.void_type(), location)
		let body = if return_type2.is_void():
			ast.expression_statement(expr: function_call)
		else:
			# Check if we need to introduce a cast to opaque value
			var value = function_call
			if needs_opaque_cast(return_type):
				return_type2 = ast.opaque_type()
				value = ast.box(value, location)
			ast.return_statement(value: Option.Some(value), location)

		let bridge_function = ast.function_def:
			is_pub: true
			name: bridge_function_name
			docstring: Option.None()
			type_parameters
			this_parameter: Option.None()
			parameters
			return_type: return_type2
			except_type
			body
			location
		# TODO: we could insert duplicate bridge functions.
		# TODO: check for duplicate bridge functions.
		new_definitions.append(ast.Definition.Function(bridge_function))
		bridge_function

fn needs_opaque_cast(ty?: ast.Type) -> bool:
	if ty.was_generic:
		if ty.is_type_parameter():
			false
		else:
			true
	else:
		false

fn uplift_this_parameter(function_def: ast.FunctionDef):
	let this_parameter = option_unwrap(function_def.this_parameter)
	function_def.this_parameter = Option.None()
	function_def.parameters.prepend(this_parameter)
