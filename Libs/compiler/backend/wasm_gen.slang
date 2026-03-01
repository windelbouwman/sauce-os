"""

WebAssembly backend
===================

Generate WebAssembly from AST.

WASM 3.0:
- strings are javascript strings via (ref extern)
- opaque pointers are (ref any)
- structs are mapped to GC structs

WASM 1.0:
- Pointers are mapped to i32 type
- floats are mapped to f64
- ints are mapped to i64
- linear memory is imported from javascript side
"""

import webassembly
import ast
from webassembly import Instruction
from listtype import List, list1
from vectype import Vector, new_vector
from optiontype import Option
from text_gen import TextGenerator
from hashmap import HashMap, new_hashmap_str
from location import location_default
from std import str_len, ord, str_get
from utils import panic, assert
from logging import log_info, log_debug

pub fn gen_webassembly(module_set: ast.ModuleSet, typectx: ast.TypeContext, output_filename: Option[str]):
	log_info("Generating WebAssembly")
	let generator = WasmGenerator(typectx)
	let wasm_module = generator.gen_module_set(modules: module_set.modules)
	let out = TextGenerator()
	out.begin(output_filename)
	webassembly.to_wat(module: wasm_module, out)
	out.end()

class WasmGenerator:
	var typectx: ast.TypeContext
	var types: List[webassembly.CompType] = List()
	var imports: List[webassembly.Import] = List()
	var globals: List[webassembly.Global] = List()
	var functions: List[webassembly.Function] = List()
	var exports: List[webassembly.Export] = List()
	var datas: List[webassembly.Data] = List()
	var code: List[webassembly.Instruction] = List()

	var struct_mapping: HashMap[ast.NodeId,int] = ast.new_hashmap_nodeid()
	var global_mapping: HashMap[ast.NodeId,int] = ast.new_hashmap_nodeid()
	var n_parameters: int = 0
	var local_variables: List[webassembly.ValueType] = List()
	var index_mapping: HashMap[str,int] = new_hashmap_str()
	var literal_offset: int = 0
	var block_stack: List[bool] = List()

	# Internally used types / functions
	var array_i16_type: int = -1
	var mk_string_fn_index: int = -1

	fn add_i16_array():
		let storage_type = webassembly.StorageType.Packed(webassembly.PackType.i16())
		let field_type = webassembly.FieldType(mutable: true, ty: storage_type)
		array_i16_type = inject_type(webassembly.CompType.Array(field_type))

	fn add_builtin():
		let params: List[webassembly.ValueType] = List()
		let results: List[webassembly.ValueType] = List()
		params.append(webassembly.ValueType.Ref(webassembly.ref_type(webassembly.HeapType.TypeIdx(array_i16_type)))) # array
		params.append(webassembly.ValueType.Num(webassembly.NumType.i32())) # start
		params.append(webassembly.ValueType.Num(webassembly.NumType.i32())) # end
		results.append(webassembly.ValueType.Ref(ty: webassembly.ref_extern_type()))

		let type_id = inject_type(webassembly.CompType.Func(params, results))

		mk_string_fn_index = imports.len()
		imports.append(webassembly.Import(module: "wasm:js-string", name: "fromCharCodeArray", ty: type_id))

	pub fn gen_module_set(modules: List[ast.ModuleDef]) -> webassembly.Module:
		add_i16_array()
		add_builtin()

		for module in modules:
			log_info("Generating external functions {module.name}")
			for definition in module.definitions:
				case definition:
					Function(function_def):
						case function_def.body:
							Intern(scoped_block):
								pass
							Extern(libname):
								gen_external_function(function_def)
							None:
								panic("Function declarations not supported")
				else:
					pass

		var counter = imports.len()
		var global_counter = 0
		for module in modules:
			for definition in module.definitions:
				case definition:
					Function(function_def):
						case function_def.body:
							Intern(scoped_block):
								let key = function_def.name
								let funcidx = counter
								index_mapping.insert(key, value: funcidx)
								let name = function_def.name
								exports.append(webassembly.Export(name, funcidx))

								counter += 1
							Extern(libname):
								pass
							None:
								panic("Function declarations not supported")
					Var(var_def):
						global_mapping.insert(key: var_def.variable.id, value: global_counter)
						global_counter += 1
				else:
					pass

		for module in modules:
			gen_module(module)

		# Tag used for exceptions:
		let tags: List[webassembly.Tag] = List()
		tags.append(webassembly.Tag(params: list1(webassembly.ValueType.Ref(webassembly.ref_type(heap_type: webassembly.HeapType.Any())))))

		# Create module:
		let wasm_module = webassembly.Module:
			types
			imports
			tags
			globals
			functions
			exports
			datas
		wasm_module

	fn gen_external_function(function_def: ast.FunctionDef):
		# log_debug("extern function def: {extern_function_def.name}")
		let funcidx = imports.len()
		index_mapping.insert(key: function_def.name, value: funcidx)

		let parameter_types: Vector[ast.Type] = new_vector()
		for parameter in function_def.parameters:
			parameter_types.append(parameter.ty)

		let func_ty = reg_signature(parameter_types, return_type: function_def.info.return_type)
		case function_def.body:
			Extern(libname):
				imports.append(webassembly.Import(module: libname, name: function_def.name, ty: func_ty))
		else:
			panic("Invalid extern function")

	fn gen_module(module: ast.ModuleDef):
		for definition in module.definitions:
			case definition:
				Function(function_def):
					case function_def.body:
						Intern(scoped_block):
							gen_function(function_def)
						Extern(libname):
							pass
						None:
							panic("Function declarations not supported")
				Struct(struct_def):
					log_debug("Struct def: {struct_def.id.name}")
				Var(var_def):
					case var_def.value:
						Intern(value):
							case value:
								Some(e):
									code = List()
									gen_expression(e)
									let g = webassembly.Global:
										mutable: var_def.variable.writable
										ty: get_wasm_type(var_def.variable.ty)
										value: code
									globals.append(g)
								None:
									panic("Uninitialized global")
						Extern(libname, initialized):
							panic("TODO: extern global")
			else:
				panic("Definition {ast.definition_to_str(definition)} not supported")

	fn get_struct_def_index(struct_def: ast.StructDef) -> int:
		if struct_mapping.contains(key: struct_def.id):
			struct_mapping.get(key: struct_def.id)
		else:
			let field_types: List[webassembly.FieldType] = List()
			for field in struct_def.fields:
				let field_type = get_wasm_type(ty: field.ty)
				let storage_type = webassembly.StorageType.Value(field_type)
				field_types.append(webassembly.FieldType(mutable: true, ty: storage_type))
			let new_index = inject_type(webassembly.CompType.Struct(field_types))
			struct_mapping.insert(key: struct_def.id, value: new_index)
			new_index

	fn get_array_type_index(element_type: ast.Type) -> int:
		let wasm_element_type = get_wasm_type(element_type)
		let storage_type = webassembly.StorageType.Value(wasm_element_type)
		let field_type = webassembly.FieldType(mutable: true, ty: storage_type)
		inject_type(webassembly.CompType.Array(field_type))

	fn get_wasm_type(ty?: ast.Type) -> webassembly.ValueType:
		if ty.is_int():
			let num_type = webassembly.NumType.i32()
			webassembly.ValueType.Num(num_type)
		elif ty.is_opaque():
			webassembly.ValueType.Ref(ty: webassembly.nullable_ref_type(webassembly.HeapType.Any()))
		elif ty.is_tycon_app():
			let tycon = ty.get_tycon()
			case tycon:
				Struct(struct_def):
					let index = get_struct_def_index(struct_def)
					webassembly.ValueType.Ref(webassembly.nullable_ref_type(webassembly.HeapType.TypeIdx(index)))
			else:
				panic("TODO: tycon")
		elif ty.is_str():
			webassembly.ValueType.Ref(ty: webassembly.ref_extern_type())
		elif ty.is_float():
			let num_type = webassembly.NumType.f64()
			webassembly.ValueType.Num(num_type)
		elif ty.is_char():
			let num_type = webassembly.NumType.i32()
			webassembly.ValueType.Num(num_type)
		elif ty.is_bool():
			let num_type = webassembly.NumType.i32()
			webassembly.ValueType.Num(num_type)
		elif ty.is_function_type():
			let parameter_types = ast.get_types_from_parameter_types(ty.get_parameter_types())
			let return_type = ty.get_return_type()
			let type_index = reg_signature(parameter_types, return_type)
			webassembly.ValueType.Ref(webassembly.ref_type(webassembly.HeapType.TypeIdx(type_index)))
		elif ty.is_unreachable():
			# TODO: unreachable != i32?
			let num_type = webassembly.NumType.i32()
			webassembly.ValueType.Num(num_type)
		elif ty.is_array():
			let index = get_array_type_index(element_type: ty.get_element_type())
			webassembly.ValueType.Ref(webassembly.RefType(nullable: true, heap_type: webassembly.HeapType.TypeIdx(index)))
		else:
			panic("TODO: {ty}!")

	fn reg_signature(parameter_types: Vector[ast.Type], return_type: ast.Type) -> int:
		let params: List[webassembly.ValueType] = List()
		let results: List[webassembly.ValueType] = List()
		for pt in parameter_types:
			params.append(get_wasm_type(pt))
		if not return_type.is_void():
			results.append(get_wasm_type(return_type))
		inject_type(webassembly.CompType.Func(params, results))

	fn inject_type(ty?: webassembly.CompType) -> int:
		let key = webassembly.comp_type_to_string(ty)
		if index_mapping.contains(key):
			index_mapping.get(key)
		else:
			let index = types.len()
			index_mapping.insert(key, value: index)
			types.append(ty)
			index

	fn gen_function(function_def: ast.FunctionDef):
		log_info("Generating code for: {ast.function_def_to_str(function_def)}")
		code = List()
		local_variables = List()
		n_parameters = 0

		let parameter_types: Vector[ast.Type] = new_vector()
		for parameter in function_def.parameters:
			let x = create_parameter(id: parameter.id, ty: parameter.ty)
			parameter_types.append(parameter.ty)
		let func_ty = reg_signature(parameter_types, return_type: function_def.info.return_type)

		case function_def.body:
			Intern(scoped_block):
				let body = scoped_block.body
				gen_statement(body)

				# Introduce an unreachable instruction, when we cannot reach this point.
				if body.ty.is_unreachable():
					emit(Instruction.ctrl_unreachable())
		else:
			panic("Function without body")

		let f = webassembly.Function:
			ty: func_ty
			locals: local_variables
			code
		functions.append(f)

	fn gen_statement(statement?: ast.Statement):
		case statement.kind:
			Break:
				let distance = get_loop()
				emit(Instruction.ctrl_br(distance + 1))

			Continue:
				let distance = get_loop()
				emit(Instruction.ctrl_br(distance))

			Compound(inner):
				for sub_statement in inner:
					gen_statement(sub_statement)

			Expr(expression):
				gen_expression(expression)

			Assignment(target, op, value):
				case target.kind:
					GetAttr(base, attr):
						let index = ast.get_struct_field_index(ty: base.ty, attr)
						let struct_def = base.ty.get_struct_def()
						let type_index = get_struct_def_index(struct_def)
						gen_expression(base)
						gen_expression(value)
						emit(Instruction.struct_set(ty: type_index, index))

					GetIndex(base, indici):
						assert(condition: indici.len() == 1, message: "Unsupported: multi-index assignment")
						let index = indici.first()
						gen_expression(base)
						gen_expression(index)
						gen_expression(value)
						let type_index = get_array_type_index(element_type: value.ty)
						emit(Instruction.array_set(ty: type_index))

					VariableRef(variable):
						gen_expression(value)
						if global_mapping.contains(key: variable.id):
							let globalidx = global_mapping.get(key: variable.id)
							emit(Instruction.global_set(globalidx))
						else:
							let localidx = get_local_index(id: variable.id)
							emit(Instruction.local_set(localidx))

					ParameterRef(parameter_def):
						let localidx = get_local_index(id: parameter_def.id)
						emit(Instruction.local_set(localidx))
				else:
					panic("Unsupported assignment target: {target}")

			Let(let_statement):
				gen_expression(let_statement.value)
				let localidx = create_local(id: let_statement.variable.id, ty: let_statement.variable.ty)
				emit(Instruction.local_set(localidx))

			If(if_statement):
				gen_expression(if_statement.condition)
				enter_block(is_loop: false)
				let block_type: webassembly.BlockType = if statement.ty.is_void() or statement.ty.is_unreachable():
					webassembly.empty_block_type()
				else:
					webassembly.one_result_block_type(get_wasm_type(statement.ty))
				emit(Instruction.ctrl_if(block_type))
				gen_statement(if_statement.true_block.body)
				emit(Instruction.ctrl_else())
				gen_statement(if_statement.false_block.body)
				emit(Instruction.ctrl_end())
				leave_block()

			While(while_statement):
				enter_block(is_loop: true)
				emit(Instruction.ctrl_block(block_type: webassembly.empty_block_type()))
				emit(Instruction.ctrl_loop(block_type: webassembly.empty_block_type()))
				gen_expression(while_statement.condition)
				emit(Instruction.i32_eqz())
				emit(Instruction.ctrl_br_if(1))
				gen_statement(while_statement.block.body)
				emit(Instruction.ctrl_br(0))
				emit(Instruction.ctrl_end())
				emit(Instruction.ctrl_end())
				leave_block()

			Pass:
				pass

			Unreachable:
				emit(Instruction.ctrl_unreachable())

			Return(value):
				case value:
					None:
						pass
					Some(v2):
						gen_expression(v2)
				emit(Instruction.ctrl_return())

			Try(try_statement):

				enter_block(is_loop: false)
				emit(Instruction.ctrl_block(block_type: webassembly.empty_block_type()))  # outer block

				enter_block(is_loop: false)
				let exception_type = webassembly.ValueType.Ref(webassembly.ref_type(webassembly.HeapType.Any()))
				emit(Instruction.ctrl_block(block_type: webassembly.one_result_block_type(exception_type)))  # handler block

				let catchers = list1(webassembly.CatchItem.Catch(tagindex: 0, labelidx: 0))
				enter_block(is_loop: false)
				emit(Instruction.ctrl_try_table(block_type: webassembly.empty_block_type(), catchers))

				gen_statement(try_statement.try_block.body)
				emit(Instruction.ctrl_end())  # end of try-table
				leave_block()
				emit(Instruction.ctrl_br(1)) # Jump to end of outer, in case of no exception

				emit(Instruction.ctrl_end()) # handler-end
				leave_block()

				# Store exception in variable
				let localidx = create_local(id: try_statement.except_var.id, ty: try_statement.except_var.ty)
				unbox_value(to_type: try_statement.except_var.ty)
				emit(Instruction.local_set(localidx))

				gen_statement(try_statement.except_block.body)

				emit(Instruction.ctrl_end()) # outer-end
				leave_block()

			Raise(value):
				box_value(value)
				emit(Instruction.ctrl_throw(0))

		else:
			panic("Not implemented: {statement}")

	fn gen_expression(expression?: ast.Expression):
		case expression.kind:
			IntLiteral(value):
				emit(Instruction.i32_const(value))
			BoolLiteral(value):
				emit(Instruction.i32_const(value: 1 if value else 0))
			StringLiteral(value):
				var index = 0
				let n = str_len(text: value)
				while index < n:
					let c = str_get(text: value, index)
					emit(Instruction.i32_const(ord(c)))
					index += 1
				emit(Instruction.array_new_fixed(ty: array_i16_type, size: n))
				emit(Instruction.i32_const(0))
				emit(Instruction.i32_const(n))
				emit(Instruction.ctrl_call(mk_string_fn_index))
			CharLiteral(value):
				emit(Instruction.i32_const(ord(value)))
			FloatLiteral(value):
				emit(Instruction.f64_const(value))
			StructLiteral(ty, values):
				for value in values:
					gen_expression(value)
				let type_index = get_struct_def_index(struct_def: ty.get_struct_def())
				emit(Instruction.struct_new(ty: type_index))
			ArrayLiteral(values):
				for value in values:
					gen_expression(value)
				let type_index = get_array_type_index(element_type: values.first().ty)
				emit(Instruction.array_new_fixed(ty: type_index, size: values.len()))
			ArrayLiteral2(size, ty):
				gen_expression(size)
				let type_index = get_array_type_index(element_type: ty)
				emit(Instruction.array_new_default(ty: type_index))
			Null:
				emit(Instruction.ref_null(ty: webassembly.HeapType.Any()))
			Binop(binop):
				gen_binop(binop)
			Unop(op, value):
				gen_unop(op, value)
			Call(call):
				gen_call(call)
			TypeCast(ty, value):
				gen_expression(value)
				gen_type_cast(from_type: value.ty, to_type: ty)
			Box(value):
				box_value(value)
			Unbox(value, to_type):
				gen_expression(value)
				unbox_value(to_type)
			GetAttr(base, attr):
				let index = ast.get_struct_field_index(ty: base.ty, attr)
				gen_expression(base)
				let struct_def = base.ty.get_struct_def()
				let type_index = get_struct_def_index(struct_def)
				emit(Instruction.struct_get(ty: type_index, index))
			GetIndex(base, indici):
				gen_expression(base)
				assert(condition: indici.len() == 1, message: "Unsupported: multi-indexing")
				let index = indici.first()
				gen_expression(index)
				let type_index = get_array_type_index(element_type: expression.ty)
				emit(Instruction.array_get(ty: type_index))
			ParameterRef(parameter_def):
				let localidx = get_local_index(id: parameter_def.id)
				emit(Instruction.local_get(localidx))
			VariableRef(variable):
				if global_mapping.contains(key: variable.id):
					let globalidx = global_mapping.get(key: variable.id)
					emit(Instruction.global_get(globalidx))
				else:
					let localidx = get_local_index(id: variable.id)
					emit(Instruction.local_get(localidx))
			FunctionRef(function_def, type_args):
				let funcidx = get_func_index(function_def)
				emit(Instruction.ref_func(funcidx))
			If(if_expression):
				gen_expression(if_expression.condition)
				let block_type = webassembly.one_result_block_type(get_wasm_type(expression.ty))
				emit(Instruction.ctrl_if(block_type))
				gen_expression(if_expression.true_value)
				emit(Instruction.ctrl_else())
				gen_expression(if_expression.false_value)
				emit(Instruction.ctrl_end())
			Stmt(statement):
				gen_statement(statement)
		else:
			panic("Not implemented expression: {expression}")

	fn box_value(value: ast.Expression):
		gen_expression(value)
		if value.ty.is_int():
			emit(Instruction.ref_i31())
		elif value.ty.is_str():
			emit(Instruction.any_convert_extern())
		elif value.ty.is_opaque() or value.ty.is_tycon_app():
			pass
		else:
			panic("TODO: box of {value.ty}")

	fn unbox_value(to_type: ast.Type):
		if to_type.is_str():
			emit(Instruction.ref_as_non_null())
			emit(Instruction.extern_convert_any())
		elif to_type.is_opaque():
			pass
		elif to_type.is_int():
			emit(Instruction.ref_cast(webassembly.nullable_ref_type(webassembly.HeapType.i31())))
			emit(Instruction.i31_get(signed: true))
		elif to_type.is_tycon_app():
			let tycon = to_type.get_tycon()
			case tycon:
				Struct(struct_def):
					let index = get_struct_def_index(struct_def)
					emit(Instruction.ref_cast(webassembly.nullable_ref_type(webassembly.HeapType.TypeIdx(index))))
			else:
				panic("TODO: unbox tycon")
		else:
			panic("TODO: unbox to {to_type}")

	fn gen_call(call: ast.FunctionCall):
		case call.callee.kind:
			FunctionRef(function_def, type_arguments):
				for argument in call.arguments:
					gen_expression(argument.value)
				let funcidx = get_func_index(function_def)
				emit(Instruction.ctrl_call(funcidx))
		else:
			# First generate callee expression:
			for argument in call.arguments:
				gen_expression(argument.value)
			gen_expression(call.callee)
			let func_type = call.callee.ty
			let parameter_types = ast.get_types_from_parameter_types(func_type.get_parameter_types())
			let return_type = func_type.get_return_type()
			let type_index = reg_signature(parameter_types, return_type)
			emit(Instruction.ctrl_call_ref(type_index))

	fn get_func_index(function_def: ast.FunctionDef) -> int:
		let key = function_def.name
		index_mapping.get(key)

	fn gen_binop(binop: ast.BinopExpression):
		gen_expression(binop.lhs)
		gen_expression(binop.rhs)
		if binop.lhs.ty.is_int():
			case binop.op:
				Add: emit(Instruction.i32_add())
				Sub: emit(Instruction.i32_sub())
				Mul: emit(Instruction.i32_mul())
				Div: emit(Instruction.i32_div_s())
				Mod: emit(Instruction.i32_rem_s())
				Less: emit(Instruction.i32_lt_s())
				LessEquals: emit(Instruction.i32_le_s())
				Greater: emit(Instruction.i32_gt_s())
				GreaterEquals: emit(Instruction.i32_ge_s())
				Equals: emit(Instruction.i32_eq())
				NotEquals: emit(Instruction.i32_ne())
				BitAnd: emit(Instruction.i32_and())
				BitXor: emit(Instruction.i32_xor())
				BitOr: emit(Instruction.i32_or())
				ShiftLeft: emit(Instruction.i32_shl())
				ShiftRight:
					# TBD: unsigned or signed shift right?
					emit(Instruction.i32_shr_u())
			else:
				panic("Invalid int binop: {ast.binary_op_to_str(binop.op)}")
		elif binop.lhs.ty.is_bool():
			case binop.op:
				And: emit(Instruction.i32_and())
				Or: emit(Instruction.i32_or())
			else:
				panic("Invalid bool binop: {ast.binary_op_to_str(binop.op)}")
		elif binop.lhs.ty.is_float():
			case binop.op:
				Add: emit(Instruction.f64_add())
				Sub: emit(Instruction.f64_sub())
				Mul: emit(Instruction.f64_mul())
				Div: emit(Instruction.f64_div())
				Less: emit(Instruction.f64_lt())
				LessEquals: emit(Instruction.f64_le())
				Greater: emit(Instruction.f64_gt())
				GreaterEquals: emit(Instruction.f64_ge())
				Equals: emit(Instruction.f64_eq())
				NotEquals: emit(Instruction.f64_ne())
			else:
				panic("Invalid str binop: {ast.binary_op_to_str(binop.op)}")
		elif binop.lhs.ty.is_char():
			case binop.op:
				Equals: emit(Instruction.i32_eq())
				NotEquals: emit(Instruction.i32_ne())
			else:
				panic("Invalid char binop: {ast.binary_op_to_str(binop.op)}")
		elif binop.lhs.ty.is_opaque():
			case binop.op:
				Equals:
					if binop.rhs.is_null():
						emit(Instruction.drop())
						emit(Instruction.ref_is_null())
					else:
						emit(Instruction.ref_eq())
			else:
				panic("Invalid opaque binop: {ast.binary_op_to_str(binop.op)}")
		else:
			panic("Binop type not supported: {binop.lhs.ty}")

	fn gen_unop(op: ast.UnaryOperator, value: ast.Expression):
		case op:
			Not:
				assert(condition: value.ty.is_bool(), message: "'not' operator only supports booleans")
				gen_expression(value)
				emit(Instruction.i32_eqz())
			Minus:
				if value.ty.is_int():
					emit(Instruction.i32_const(0))
					gen_expression(value)
					emit(Instruction.i32_sub())
				elif value.ty.is_float():
					gen_expression(value)
					emit(Instruction.f64_neg())
				else:
					panic("unop(-) for {value.ty}")

	fn gen_type_cast(from_type: ast.Type, to_type: ast.Type):
		if to_type.is_float():
			if from_type.is_int():
				emit(Instruction.f64_convert_i32_s())
			elif from_type.is_float():
				pass
			else:
				panic("TODO: cast {from_type} to float")
		elif to_type.is_int():
			if from_type.is_int():
				pass
			elif from_type.is_float():
				emit(Instruction.i32_trunc_f64_s())
			else:
				panic("TODO: cast {from_type} to int")
		else:
			panic("TODO: cast to {to_type}")

	fn get_local_index(id: ast.NodeId) -> int:
		index_mapping.get(key: ast.node_id_to_string(id))

	fn create_parameter(id: ast.NodeId, ty: ast.Type) -> int:
		let idx = n_parameters
		n_parameters += 1
		index_mapping.insert(key: ast.node_id_to_string(id), value: idx)
		idx

	fn create_local(id: ast.NodeId, ty: ast.Type) -> int:
		let idx = local_variables.len() + n_parameters
		let wasm_ty = get_wasm_type(ty)
		local_variables.append(wasm_ty)
		index_mapping.insert(key: ast.node_id_to_string(id), value: idx)
		idx

	fn emit(instruction?: Instruction):
		# log_info("WASM INSTR> {webassembly.to_string(instruction)}")
		code.append(instruction)

	fn enter_block(is_loop: bool):
		block_stack.prepend(is_loop)

	fn leave_block():
		block_stack.drop_front()

	fn get_loop() -> int:
		var index = 0
		for b in block_stack:
			if b:
				return index
			else:
				index += 1
		panic("Not in a loop!")
