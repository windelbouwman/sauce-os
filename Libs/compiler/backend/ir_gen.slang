# generate bytecode

import ast
from listtype import List
from optiontype import option_unwrap, Option
from vectype import Vector, new_vector, new_vector_with_capacity
from hashmap import HashMap, new_hashmap_int, new_hashmap_str
from utils import panic, assert
from logging import log_info, log_debug, log_trace
import dbginfo
from bc import Instruction
import bc

pub fn gen_bytecode(module_set: ast.ModuleSet, debug: Option[dbginfo.DbgInfo]) -> bc.Program:
	let g = BytecodeGenerator(m_debug: debug)
	g.forward_declarations(module_set)
	for module in module_set.modules:
		g.gen_prog(module)
	bc.Program(functions: g.functions, structs: g.structs, globals: g.global_variables, extern_functions: g.extern_functions)

pub fn gen_expression_bytecode(expression: ast.Expression) -> Vector[Instruction]:
	let g = BytecodeGenerator(m_debug: Option.None())
	g.gen_expression(expression)
	g.emit(Instruction.Return(n_args: 1))
	g.get_relocated_instructions()

enum ControlBlock:
	LoopBlock(loop_: Loop)
	TryBlock(try_: Try)
	Scope(variables: List[ast.Variable])

struct Loop:
	continue_label: int
	break_label: int

struct Try:
	except_label: int
	except_var_index: int

class BytecodeGenerator:
	var id_counter: int = 1
	var is_reachable: bool = true
	var m_except_type: ast.Type = ast.undefined_type()
	var m_return_type: ast.Type = ast.undefined_type()
	var code: Vector[Instruction] = new_vector()

	pub var global_variables: Vector[bc.Global] = new_vector()
	var global_var_mapping: HashMap[ast.NodeId,int] = ast.new_hashmap_nodeid()
	var local_variables: Vector[bc.TypedName] = new_vector()
	var local_var_mapping: HashMap[ast.NodeId,int] = ast.new_hashmap_nodeid()
	var label_mapping: HashMap[int,int] = new_hashmap_int()
	var struct_mapping: HashMap[ast.NodeId,int] = ast.new_hashmap_nodeid()
	pub var extern_functions: Vector[bc.ExternFunction] = new_vector()

	pub var structs: Vector[bc.Struct] = new_vector()
	pub var functions: Vector[bc.Function] = new_vector()
	var function_map: HashMap[str,int] = new_hashmap_str()
	var block_stack: List[ControlBlock] = List()

	var m_debug: Option[dbginfo.DbgInfo]

	pub fn forward_declarations(module_set: ast.ModuleSet):
		# struct forward declarations:
		var index = 0
		for module in module_set.modules:
			for definition in module.definitions:
				case definition:
					Struct(struct_def):
						struct_mapping.insert(key: struct_def.id, value: index)
						index += 1
				else:
					pass

		# Extern function forward delcarations:
		for module in module_set.modules:
			for definition in module.definitions:
				case definition:
					Struct(struct_def):
						assert(condition: not struct_def.is_union, message: "Unions not supported in bytecode.")
						let fields2: List[bc.TypedName] = List()
						for field1 in struct_def.fields:
							fields2.append(bc.TypedName(name: field1.name, ty: get_bc_type(field1.ty)))
						structs.append(bc.Struct(name: struct_def.id.name, fields: fields2))
					Var(variable_def):
						gen_global_variable(variable_def)
					Function(function_def):
						case function_def.body:
							Intern(scoped_block):
								pass
							Extern(libname):
								gen_extern_function(function_def)
							None:
								panic("Function declarations not supported")
				else:
					pass

		var func_index = extern_functions.len()
		for module in module_set.modules:
			for definition in module.definitions:
				case definition:
					Function(function_def):
						case function_def.body:
							Intern(scoped_block):
								function_map.insert(key: function_def.name, value: func_index)
								func_index += 1
								case m_debug:
									Some(info):
										case module.filename:
											Some(filename2):
												info.add_function(name: function_def.name, filename: filename2, location: function_def.location)
											None:
												pass
									None:
										pass
							Extern(libname):
								pass
							None:
								panic("Function declarations not supported")
				else:
					pass

	pub fn gen_prog(module: ast.ModuleDef):
		log_info("Generating bytecode for {module.name}")
		for definition in module.definitions:
			case definition:
				Function(function_def):
					gen_func(function_def)
				Var(variable_def):
					gen_global_init(variable_def)
				Enum(enum_def):
					panic("Enum not supported, please rewrite")
				Class(class_def):
					panic("Classes are not supported, please rewrite into structs with functions.")
			else:
				pass

	fn gen_global_variable(variable_def: ast.VariableDef):
		""" Create global variable """
		let global_index = global_variables.len()
		let name = get_name(variable_def.variable.id)
		let value: Option[Vector[bc.Instruction]] = Option.None()
		let global_variable = bc.Global(name, ty: get_bc_type(variable_def.variable.ty), value)
		global_variables.append(global_variable)
		global_var_mapping.insert(key: variable_def.variable.id, value: global_index)

	fn gen_global_init(variable_def: ast.VariableDef):
		""" Initialize global variable """
		let global_index = global_var_mapping.get(key: variable_def.variable.id)
		let global_variable = global_variables[global_index]
		case variable_def.value:
			Intern(ival):
				begin_code()
				gen_expression(option_unwrap(ival))
				emit(Instruction.Return(n_args: 1))
				global_variable.value = Option.Some(get_relocated_instructions())
			Extern(libname, initialized):
				pass

	fn gen_extern_function(function_def: ast.FunctionDef):
		let func_index = extern_functions.len()
		let name = function_def.name

		let parameters: Vector[bc.TypedName] = new_vector_with_capacity(capacity: function_def.parameters.len())
		for parameter in function_def.parameters:
			parameters.append(bc.TypedName(name: parameter.id.name, ty: get_bc_type(parameter.ty)))

		let return_types: Vector[bc.Type] = new_vector()
		var no_return = false
		if function_def.info.return_type.is_void():
			pass
		elif function_def.info.return_type.is_unreachable():
			no_return = true
		else:
			return_types.append(get_bc_type(function_def.info.return_type))

		if not function_def.info.except_type.is_void():
			return_types.append(bc.Type.Ptr())

		let extern_function = bc.ExternFunction(name, parameters, return_types, no_return)
		extern_functions.append(extern_function)
		function_map.insert(key: name, value: func_index)

	fn gen_func(function_def: ast.FunctionDef):
		case function_def.body:
			Intern(scoped_block):
				log_debug("generate bytecode for {function_def.name}")
				local_var_mapping.clear()
				let parameters: Vector[bc.TypedName] = new_vector_with_capacity(capacity: function_def.parameters.len())
				for parameter in function_def.parameters:
					let p2 = bc.TypedName(name: parameter.id.name, ty: get_bc_type(parameter.ty))
					let parameter_index = parameters.len()
					local_var_mapping.insert(key: parameter.id, value: parameter_index)
					parameters.append(p2)
				let return_types: Vector[bc.Type] = new_vector()
				var no_return = false
				if function_def.info.return_type.is_void():
					pass
				elif function_def.info.return_type.is_unreachable():
					no_return = true
				else:
					return_types.append(get_bc_type(function_def.info.return_type))
				if not function_def.info.except_type.is_void():
					return_types.append(bc.Type.Ptr())
				begin_code()
				local_variables = new_vector()
				# TODO: could be stored as 'info'?
				m_return_type = function_def.info.return_type
				m_except_type = function_def.info.except_type

				# Emit return to void function, or unreachable
				if scoped_block.body.ty.is_void():
					gen_scoped_block(scoped_block, target: Option.None())
					if m_except_type.is_void():
						emit(Instruction.Return(n_arg: 0))
					else:
						emit(Instruction.Literal(bc.LiteralValue.Null()))
						emit(Instruction.Return(n_arg: 1))
				elif scoped_block.body.ty.is_unreachable():
					gen_scoped_block(scoped_block, target: Option.None())
					emit(Instruction.Unreachable())
				else:
					# If the last statement is an expression, we do not need the SNAG variable.
					if scoped_block.body.last_is_expr():
						gen_scoped_block(scoped_block, target: Option.None())
					else:
						let ty = get_bc_type(scoped_block.body.ty)
						let index = new_local(name: "__SNAG", ty)
						gen_scoped_block(scoped_block, target: Option.Some(index))
						emit(Instruction.LocalGet(index))
					if m_except_type.is_void():
						emit(Instruction.Return(n_arg: 1))
					else:
						emit(Instruction.Literal(bc.LiteralValue.Null()))
						emit(Instruction.Return(n_arg: 2))

				let instructions = get_relocated_instructions()
				let locals = local_variables
				let name = function_def.name
				functions.append(bc.Function(name, is_pub: function_def.is_pub, parameters, return_types, no_return, locals, instructions))
			Extern(libname):
				pass
			None:
				panic("Function declarations not supported")

	fn goto_inner_loop() -> Loop:
		for block in block_stack:
			case block:
				LoopBlock(loop_):
					return loop_
			else:
				block_cleanup(block)
		panic("Not in a loop!")

	fn goto_inner_try() -> Option[Try]:
		for block in block_stack:
			case block:
				TryBlock(try_):
					return Option.Some(try_)
			else:
				block_cleanup(block)
		Option.None()

	fn gen_scoped_block(scoped_block?: ast.ScopedBlock, target: Option[int]):
		# scoped_block.scope
		# let variables: List[ast.Variable] = List()
		# scoped_block.scope.dump()
		# for symbol in scoped_block.scope.get_symbols():
		#     case symbol:
		#         Var(variable):
		#             print("Name: {variable.id.name}")
		#             variables.append(variable)
		#     else:
		#         pass
		# enter_block(block: ControlBlock.Scope(variables))
		gen_statement(scoped_block.body, target)
		# leave_block()

	fn gen_statement(statement?: ast.Statement, target: Option[int]):
		case statement.kind:
			Pass:
				pass
			Break:
				let inner_most_loop = goto_inner_loop()
				jump(target: inner_most_loop.break_label)
			Continue:
				let inner_most_loop = goto_inner_loop()
				jump(target: inner_most_loop.continue_label)
			Expr(expr):
				gen_expression(expr)
				if expr.ty.is_void():
					case target:
						Some(index):
							panic("No value to store.")
						None:
							pass
				elif expr.ty.is_unreachable():
					pass
				else:
					case target:
						Some(index):
							emit(Instruction.LocalSet(index))
						None:
							pass
			Assignment(target, op, value):
				gen_assignment(target, op, value)
			While(while_statement):
				gen_while_statement(while_statement)
			If(if_statement):
				gen_if_statement(if_statement, target)
			Loop(loop_statement):
				panic("Loop not implemented")
			For(for_statement):
				panic("For-statement not supported")
			Try(try_statement):
				gen_try_statement(try_statement)
			Case(case_statement):
				panic("Case-statement not supported")
			Let(let_statement):
				let var_index = add_local(variable: let_statement.variable)
				case let_statement.value.kind:
					Stmt(statement2):
						gen_statement(statement2, target: Option.Some(var_index))
				else:
					gen_expression(let_statement.value)
					emit(Instruction.LocalSet(var_index))
			Compound(inner):
				let n = inner.len()
				var i = 0
				for s in inner:
					i += 1
					if i == n:
						gen_statement(s, target)
					else:
						gen_statement(s, target: Option.None())
			Switch(switch_statement):
				panic("Switch not implemented")
			Unreachable:
				emit(Instruction.Unreachable())
				is_reachable = false
			Return(opt_val):
				gen_return(opt_val)
			Raise(value):
				gen_raise(value)

	fn gen_return(opt_val: Option[ast.Expression]):
		var n_args = 0

		case opt_val:
			Some(val):
				gen_expression(val)
				n_args += 1
			None:
				pass

		if not m_except_type.is_void():
			emit(Instruction.Literal(bc.LiteralValue.Null()))
			n_args += 1

		for block in block_stack:
			block_cleanup(block)

		emit(Instruction.Return(n_args))
		is_reachable = false

	fn gen_raise(value: ast.Expression):
		gen_expression(value)
		actual_do_raise()

	fn actual_do_raise():
		""" Do local jump, or return special marker value, which lives on top of stack now."""
		case goto_inner_try():
			Some(try_):
				emit(Instruction.LocalSet(try_.except_var_index))
				jump(try_.except_label)
			None:
				var n_args = 1
				if not (m_return_type.is_void() or m_return_type.is_unreachable()):
					emit(Instruction.Literal(bc.LiteralValue.Null()))
					emit(Instruction.Swap())
					n_args += 1
				emit(Instruction.Return(n_args))
				is_reachable = false

	fn gen_assignment(target: ast.Expression, op: Option[ast.BinaryOperator], value: ast.Expression):
		case target.kind:
			GetAttr(base, attr):
				gen_expression(base)
				let index = get_attr_index(ty: base.ty, attr)
				case op:
					Some(op):
						emit(Instruction.Dup())
						emit(Instruction.GetAttr(index))
						gen_expression(value)
						gen_binop(op)
					None:
						gen_expression(value)
				emit(Instruction.SetAttr(index))
			GetIndex(base, indici):
				gen_expression(base)
				assert(condition: indici.len() == 1, message: "Unsupported: multi-indexing")
				let index = indici.first()
				gen_expression(index)
				case op:
					Some(op):
						emit(Instruction.GetIndex())
						gen_expression(value)
						gen_binop(op)
						# TBD: we do want to duplicate base and index here
						panic("x[y] += not implemented")
					None:
						gen_expression(value)
				emit(Instruction.SetIndex())
			VariableRef(variable):
				if is_local_variable(variable):
					let index = get_local_index(variable)
					case op:
						Some(op):
							emit(Instruction.LocalGet(index))
							gen_expression(value)
							gen_binop(op)
						None:
							gen_expression(value)
					emit(Instruction.LocalSet(index))
				else:
					let index = get_global_index(variable)
					case op:
						Some(op):
							emit(Instruction.GlobalGet(index))
							gen_expression(value)
							gen_binop(op)
						None:
							gen_expression(value)
					emit(Instruction.GlobalSet(index))
			ParameterRef(parameter_def):
				let parameter_index = get_parameter_index(parameter_def)
				case op:
					Some(op):
						emit(Instruction.ParameterGet(parameter_index))
						gen_expression(value)
						gen_binop(op)
					None:
						gen_expression(value)
				emit(Instruction.ParameterSet(parameter_index))

		else:
			panic("Cannot assign: {target}")

	fn gen_try_statement(try_statement: ast.TryStatement):
		log_trace("gen_try_statement")
		let try_label = new_label()
		let except_label = new_label()
		let final_label = new_label()

		let except_var_index = add_local(variable: try_statement.except_var)

		set_label(try_label)
		enter_block(block: ControlBlock.TryBlock(Try(except_label, except_var_index)))
		gen_scoped_block(try_statement.try_block, target: Option.None())
		leave_block()
		jump(final_label)

		set_label(except_label)
		gen_scoped_block(try_statement.except_block, target: Option.None())
		jump(final_label)

		set_label(final_label)

	fn gen_while_statement(while_statement: ast.WhileStatement):
		log_trace("gen_while_statement")
		let test_label = new_label()
		let body_label = new_label()
		let final_label = new_label()
		enter_block(block: ControlBlock.LoopBlock(loop_: Loop(continue_label: test_label, break_label: final_label)))

		set_label(test_label)
		gen_condition(condition: while_statement.condition, true_label: body_label, false_label: final_label)

		set_label(body_label)
		gen_scoped_block(while_statement.block, target: Option.None())
		jump(test_label)

		leave_block()
		set_label(final_label)

	fn gen_if_statement(if_statement: ast.IfStatement, target: Option[int]):
		let true_label = new_label()
		let false_label = new_label()
		let final_label = new_label()

		gen_condition(condition: if_statement.condition, true_label, false_label)

		set_label(true_label)
		gen_scoped_block(if_statement.true_block, target)
		let reach1 = is_reachable
		jump(final_label)

		set_label(false_label)
		gen_scoped_block(if_statement.false_block, target)
		let reach2 = is_reachable
		jump(final_label)

		if reach1 or reach2:
			set_label(final_label)

	fn gen_condition(condition: ast.Expression, true_label: int, false_label: int):
		# Generate short circuit logic for 'and' and 'or' conditions
		# Otherwise, evaluate the condition, and use jump-if
		case condition.kind:
			Binop(binop):
				case binop.op:
					And:
						# Both sides must be true
						# If the first condition is true, we must check the second one.
						let middle_label = new_label()
						gen_condition(condition: binop.lhs, true_label: middle_label, false_label)
						set_label(middle_label)
						gen_condition(condition: binop.rhs, true_label, false_label)
					Or:
						# One condition must be true must be true
						# If the first condition is true, we are done. Otherwise, check the second condition
						let middle_label = new_label()
						gen_condition(condition: binop.lhs, true_label, false_label: middle_label)
						set_label(middle_label)
						gen_condition(condition: binop.rhs, true_label, false_label)
					Equals:
						gen_comparison(lhs: binop.lhs, op: bc.ComparisonOperator.Equals(), rhs: binop.rhs, true_label, false_label)
					NotEquals:
						gen_comparison(lhs: binop.lhs, op: bc.ComparisonOperator.NotEquals(), rhs: binop.rhs, true_label, false_label)
					Less:
						gen_comparison(lhs: binop.lhs, op: bc.ComparisonOperator.Less(), rhs: binop.rhs, true_label, false_label)
					LessEquals:
						gen_comparison(lhs: binop.lhs, op: bc.ComparisonOperator.LessEquals(), rhs: binop.rhs, true_label, false_label)
					Greater:
						gen_comparison(lhs: binop.lhs, op: bc.ComparisonOperator.Greater(), rhs: binop.rhs, true_label, false_label)
					GreaterEquals:
						gen_comparison(lhs: binop.lhs, op: bc.ComparisonOperator.GreaterEquals(), rhs: binop.rhs, true_label, false_label)
				else:
					gen_expression(condition)
					jump_if_true(true_label, false_label)
			Unop(op, rhs):
				case op:
					Not:
						gen_condition(condition: rhs, true_label: false_label, false_label: true_label)
				else:
					gen_expression(condition)
					jump_if_true(true_label, false_label)
		else:
			gen_expression(condition)
			jump_if_true(true_label, false_label)

	fn gen_comparison(lhs: ast.Expression, op: bc.ComparisonOperator, rhs: ast.Expression, true_label: int, false_label: int):
		gen_expression(lhs)
		gen_expression(rhs)
		jump_if(op, true_label, false_label)

	fn jump_if_true(true_label: int, false_label: int):
		emit(Instruction.Literal(bc.LiteralValue.Bool(value: true)))
		jump_if(op: bc.ComparisonOperator.Equals(), true_label, false_label)

	fn condition_as_value(condition: ast.Expression):
		# Evaluate a condition into a value on the stack.

		# Create a local variable for the result:
		let ty = bc.Type.Bool()
		let index = new_local(name: "tmp", ty)

		# Evaluate the condition, and branch:
		let true_label = new_label()
		let false_label = new_label()
		let final_label = new_label()
		gen_condition(condition, true_label, false_label)

		set_label(true_label)
		emit(Instruction.Literal(bc.LiteralValue.Bool(value: true)))
		emit(Instruction.LocalSet(index))
		jump(final_label)

		set_label(false_label)
		emit(Instruction.Literal(bc.LiteralValue.Bool(value: false)))
		emit(Instruction.LocalSet(index))
		jump(final_label)

		set_label(final_label)
		emit(Instruction.LocalGet(index))

	pub fn gen_expression(expression?: ast.Expression):
		case expression.kind:
			Call(call):
				gen_call(call)
			GetAttr(base, attr):
				gen_expression(base)
				let index = get_attr_index(ty: base.ty, attr)
				emit(Instruction.GetAttr(index))
			GetIndex(base, indici):
				gen_expression(base)
				assert(condition: indici.len() == 1, message: "Unsupported: multi-indexing")
				let index = indici.first()
				gen_expression(index)
				emit(Instruction.GetIndex())
			Binop(binop):
				case binop.op:
					And:
						condition_as_value(condition: expression)
					Or:
						condition_as_value(condition: expression)
					NotEquals:
						condition_as_value(condition: expression)
					Equals:
						condition_as_value(condition: expression)
					Greater:
						condition_as_value(condition: expression)
					GreaterEquals:
						condition_as_value(condition: expression)
					Less:
						condition_as_value(condition: expression)
					LessEquals:
						condition_as_value(condition: expression)
				else:
					gen_binop_expr(binop)
			Unop(op, value):
				gen_expression(value)
				case op:
					Not:
						emit(Instruction.Not())
					Minus:
						emit(Instruction.Neg())
			IntLiteral(value):
				emit(Instruction.Literal(bc.LiteralValue.Int(value)))
			FloatLiteral(value):
				emit(Instruction.Literal(bc.LiteralValue.Float(value)))
			StringLiteral(value):
				emit(Instruction.Literal(bc.LiteralValue.Str(value)))
			CharLiteral(value):
				emit(Instruction.Literal(bc.LiteralValue.Char(value)))
			BoolLiteral(value):
				emit(Instruction.Literal(bc.LiteralValue.Bool(value)))
			Null:
				emit(Instruction.Literal(bc.LiteralValue.Null()))
			VariableRef(variable):
				if is_local_variable(variable):
					let var_index = get_local_index(variable)
					emit(Instruction.LocalGet(var_index))
				else:
					let var_index = get_global_index(variable)
					emit(Instruction.GlobalGet(var_index))
			FunctionRef(function_def, type_arguments):
				let funcidx = function_map.get(key: function_def.name)
				emit(Instruction.LoadFunc(funcidx))
			ParameterRef(parameter_def):
				let parameter_index = get_parameter_index(parameter_def)
				emit(Instruction.ParameterGet(parameter_index))
			StructLiteral(ty, values):
				let struct_def = ty.get_struct_def()
				let struct_index = struct_mapping.get(key: struct_def.id)
				emit(Instruction.StructLiteral(struct_index))
				var index = 0
				for value in values:
					emit(Instruction.Dup())
					gen_expression(value)
					emit(Instruction.SetAttr(index))
					index += 1
			ArrayLiteral(values):
				let size = values.len()
				emit(Instruction.Literal(bc.LiteralValue.Int(size)))
				let ty = get_bc_type(values.first().ty)
				emit(Instruction.ArrayLiteral(ty))
				var index = 0
				for value in values:
					emit(Instruction.Dup())
					emit(Instruction.Literal(bc.LiteralValue.Int(index)))
					gen_expression(value)
					emit(Instruction.SetIndex())
					index += 1
			ArrayLiteral2(size, ty):
				gen_expression(size)
				emit(Instruction.ArrayLiteral(get_bc_type(ty)))
			TypeCast(ty, value):
				gen_expression(value)
				if ty.is_float():
					if value.ty.is_int():
						emit(Instruction.IntToFloat())
					elif value.ty.is_float():
						# No-op
						# TODO: cast from 32 to 64 bits and vice versa?
						pass
					else:
						panic("cannot cast to float: {value.ty}")
				elif ty.is_int():
					if value.ty.is_float():
						emit(Instruction.FloatToInt())
					elif value.ty.is_int():
						let signed = ty.is_signed_int()
						let bits = ty.get_bits()
						emit(Instruction.IntCast(signed, bits))
					else:
						panic("cannot cast to int: {value.ty}")
				else:
					panic("unsupported type-casting from {value.ty} to {ty}")
			Box(value):
				gen_expression(value)
				emit(Instruction.ToOpaque(get_bc_type(value.ty)))
			Unbox(value, to_type):
				gen_expression(value)
				emit(Instruction.FromOpaque(get_bc_type(to_type)))
			If(if_expression):
				gen_if_expression(if_expression)
		else:
			panic("gen_expression: Unsupported: {expression}")

	fn gen_if_expression(if_expression: ast.IfExpression):
		let index = new_local(name: "tmp", ty: get_bc_type(if_expression.true_value.ty))

		let true_label = new_label()
		let false_label = new_label()
		let final_label = new_label()

		gen_condition(condition: if_expression.condition, true_label, false_label)

		set_label(true_label)
		gen_expression(if_expression.true_value)
		emit(Instruction.LocalSet(index))
		jump(final_label)

		set_label(false_label)
		gen_expression(if_expression.false_value)
		emit(Instruction.LocalSet(index))
		jump(final_label)

		set_label(final_label)
		emit(Instruction.LocalGet(index))

	fn gen_call(call: ast.FunctionCall):
		for argument in call.arguments:
			gen_expression(argument.value)

		case call.callee.kind:
			FunctionRef(function_def, type_args):
				let key = function_def.name
				let funcidx = function_map.get(key)
				emit(Instruction.Call(funcidx))

				# If function might raise exception, we handle it!
				if not function_def.info.except_type.is_void():
					# Exception lives on top of stack now, below it lives return value (if any)
					let index = new_local(name: "exception_value", ty: bc.Type.Ptr())
					emit(Instruction.LocalSet(index))

					let optional_return_value = if not (function_def.info.return_type.is_void() or function_def.info.return_type.is_unreachable()):
						let index2 = new_local(name: "return_value", ty: get_bc_type(function_def.info.return_type))
						emit(Instruction.LocalSet(index2))
						Option.Some(index2)
					else:
						Option.None()

					let true_label = new_label()
					let false_label = new_label()
					emit(Instruction.Literal(bc.LiteralValue.Null()))
					emit(Instruction.LocalGet(index))
					jump_if(op: bc.ComparisonOperator.Equals(), true_label, false_label)

					set_label(false_label)
					emit(Instruction.LocalGet(index))
					# unbox?
					actual_do_raise()

					set_label(true_label)
					case optional_return_value:
						Some(index2):
							emit(Instruction.LocalGet(index2))
						None:
							pass

		else:
			gen_indirect_call(callee: call.callee)

		# ??
		#if function_def.info.no_return:
		#    is_reachable = false

	fn gen_indirect_call(callee: ast.Expression):
		gen_expression(callee)
		let pty2 = callee.ty.get_parameter_types()
		let parameter_types: Vector[bc.TypedName] = new_vector_with_capacity(capacity: pty2.len())
		for p2 in pty2:
			parameter_types.append(bc.TypedName(name: "x", ty: get_bc_type(p2.ty)))
		let return_type2 = callee.ty.get_return_type()
		let return_types: Vector[bc.Type] = new_vector()
		if not return_type2.is_void():
			return_types.append(get_bc_type(return_type2))
		if not callee.ty.get_except_type().is_void():
			panic("Indirect calls which raise exceptions not supported")
		emit(Instruction.CallIndirect(parameter_types, return_types))

	fn gen_binop_expr(binop: ast.BinopExpression):
		gen_expression(binop.lhs)
		gen_expression(binop.rhs)
		gen_binop(op: binop.op)

	fn gen_binop(op: ast.BinaryOperator):
		case op:
			Add:
				emit(Instruction.Binop(op: bc.BinaryOperator.Add()))
			Sub:
				emit(Instruction.Binop(op: bc.BinaryOperator.Sub()))
			Mul:
				emit(Instruction.Binop(op: bc.BinaryOperator.Multiply()))
			Div:
				emit(Instruction.Binop(op: bc.BinaryOperator.Divide()))
			Mod:
				emit(Instruction.Binop(op: bc.BinaryOperator.Modulo()))
			NotEquals:
				panic("No bytecode for not-equals")
			Equals:
				panic("No bytecode for equals")
			Greater:
				panic("No bytecode for greater")
			GreaterEquals:
				panic("No bytecode for greater-equals")
			Less:
				panic("No bytecode for less")
			LessEquals:
				panic("No bytecode for less-equals")
			And:
				panic("unreachable: and")
			Or:
				panic("unreachable: or")
			BitAnd:
				emit(Instruction.Bitop(op: bc.BitOperator.And()))
			BitXor:
				emit(Instruction.Bitop(op: bc.BitOperator.Xor()))
			BitOr:
				emit(Instruction.Bitop(op: bc.BitOperator.Or()))
			ShiftLeft:
				emit(Instruction.Bitop(op: bc.BitOperator.Shl()))
			ShiftRight:
				emit(Instruction.Bitop(op: bc.BitOperator.Shr()))

	fn new_label() -> int:
		gen_id()

	fn set_label(label?: int):
		let index = code.len()
		label_mapping.insert(key: label, value: index)
		is_reachable = true

	fn translate_label(label?: int) -> int:
		label_mapping.get(key: label)

	fn begin_code():
		label_mapping = new_hashmap_int()
		code = new_vector()
		is_reachable = true

	pub fn get_relocated_instructions() -> Vector[Instruction]:
		# Apply relocations to labels
		let instructions: Vector[Instruction] = new_vector()
		for instruction in code:
			case instruction:
				Jump(label):
					label = translate_label(label)
					instructions.append(Instruction.Jump(label))
				JumpIf(op, label1, label2):
					label1 = translate_label(label1)
					label2 = translate_label(label2)
					instructions.append(Instruction.JumpIf(op, label1, label2))
			else:
				instructions.append(instruction)
		instructions

	fn jump(label?: int):
		emit(Instruction.Jump(target: label))
		is_reachable = false

	fn jump_if(op: bc.ComparisonOperator, true_label: int, false_label: int):
		emit(Instruction.JumpIf(op, label1: true_label, label2: false_label))
		is_reachable = false

	fn add_local(variable: ast.Variable) -> int:
		# Add a local variable!
		let ty = get_bc_type(variable.ty)
		let index = new_local(name: variable.id.name, ty)
		local_var_mapping.insert(key: variable.id, value: index)
		index

	fn new_local(name: str, ty: bc.Type) -> int:
		let index = local_variables.len()
		let local = bc.TypedName(name, ty)
		local_variables.append(local)
		index

	fn is_local_variable(variable: ast.Variable) -> bool:
		local_var_mapping.contains(key: variable.id)

	fn get_local_index(variable: ast.Variable) -> int:
		local_var_mapping.get(key: variable.id)

	fn get_global_index(variable: ast.Variable) -> int:
		global_var_mapping.get(key: variable.id)

	fn get_parameter_index(parameter_def: ast.ParameterDef) -> int:
		local_var_mapping.get(key: parameter_def.id)

	fn get_bc_type(ty2?: ast.Type) -> bc.Type:
		# Determine the bytecode type for the given ast type
		if ty2.is_int():
			let signed = ty2.is_signed_int()
			let bits = ty2.get_bits()
			bc.Type.Int(signed, bits)
		elif ty2.is_float():
			let bits = ty2.get_bits()
			bc.Type.Float(bits)
		elif ty2.is_str():
			bc.Type.Str()
		elif ty2.is_struct():
			let struct_def = ty2.get_struct_def()
			let index = struct_mapping.get(key: struct_def.id)
			bc.Type.StructRef(index)
		elif ty2.is_function_type():
			let parameter_types2 = ty2.get_parameter_types()
			let parameter_types: List[bc.Type] = List()
			for p2 in parameter_types2:
				parameter_types.append(get_bc_type(p2.ty))
			let return_types: Vector[bc.Type] = new_vector()
			let return_type2 = ty2.get_return_type()
			if not return_type2.is_void():
				return_types.append(get_bc_type(return_type2))
			let except_type2 = ty2.get_except_type()
			if not except_type2.is_void():
				return_types.append(bc.Type.Ptr())
			bc.Type.Function(parameter_types, return_types)
		elif ty2.is_type_parameter():
			bc.Type.Ptr()
		elif ty2.is_bool():
			bc.Type.Bool()
		elif ty2.is_char():
			bc.Type.Char()
		elif ty2.is_opaque():
			bc.Type.Ptr()
		elif ty2.is_array():
			let element_type2 = ty2.get_element_type()
			bc.Type.Array(get_bc_type(element_type2))
		else:
			panic("get_bc_type: Type {ty2} not supported")

	fn enter_block(block: ControlBlock):
		block_stack.prepend(block)

	fn leave_block():
		let block = block_stack.pop_front()
		block_cleanup(block)

	fn block_cleanup(block: ControlBlock):
		case block:
			Scope(variables):
				for variable in variables:
					emit(Instruction.DecRef(index: get_local_index(variable)))
		else:
			pass

	pub fn emit(instruction?: Instruction):
		# print("Inst: {bc.instruction_to_string(instruction)}")
		if is_reachable:
			code.append(instruction)

	fn get_name(id?: ast.NodeId) -> str:
		"X{id.id}_{id.name}"

	fn gen_id() -> int:
		let x = id_counter
		id_counter += 1
		x


fn get_attr_index(ty: ast.Type, attr: str) -> int:
	let struct_def = ty.get_struct_def()
	var index = 0
	for field in struct_def.fields:
		if field.name == attr:
			return index
		index += 1
	panic("No field: {attr}")
