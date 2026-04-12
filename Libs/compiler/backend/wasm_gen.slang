module compiler.wasm_gen
"""WebAssembly backend
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
import std
from webassembly import Instruction
from base.listtype import List, list1
from base.vectype import Vector, new_vector
from base.bytes import ByteArray
from base.optiontype import Option
from text_gen import TextGenerator
from base.hashmap import HashMap, new_hashmap_str
from location import location_default
from std import str_len, ord, str_get
from base.utils import panic, assert
from base.logging import log_info, log_debug

pub fn gen_webassembly_text(module_defs: List[ast.ModuleDef], typectx: ast.TypeContext, output_filename: Option[str]):
	let wasm_module = gen_webassembly_module(module_defs, typectx)
	let out = TextGenerator()
	out.m_one_tab = "  "
	out.begin(output_filename)
	webassembly.to_wat(wasm_module, out)
	out.end()

pub fn gen_webassembly_binary(module_defs: List[ast.ModuleDef], typectx: ast.TypeContext, filename: str):
	let wasm_module = gen_webassembly_module(module_defs, typectx)
	let data = webassembly.to_wasm(wasm_module)
	let handle = std.file_open(filename, mode: "wb")
	let written = std.file_write_n_bytes(handle, buffer: data.as_array(), bufsize: data.len())
	assert(condition: written == data.len(), message: "file_write_n_bytes failed")
	std.file_close(handle)

pub fn gen_webassembly_module(module_defs: List[ast.ModuleDef], typectx: ast.TypeContext) -> webassembly.Module:
	log_info("Generating WebAssembly")
	let generator = WasmGenerator(typectx)
	let wasm_module = generator.gen_module_defs(modules: module_defs)
	wasm_module

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
	var m_string_data: ByteArray = ByteArray()

	# Internally used types / functions
	var array_i16_type: int = -1
	var f64_box_type: int = -1
	var f32_box_type: int = -1
	var i64_box_type: int = -1
	var i32_box_type: int = -1
	var mk_string_fn_index: int = -1

	var func_counter: int = 0
	var global_counter: int = 0

	fn add_i16_array():
		let storage_type = webassembly.StorageType.Packed(webassembly.PackType.i16())
		let field_type = webassembly.FieldType(mutable: true, ty: storage_type)
		array_i16_type = inject_type(webassembly.CompType.Array(field_type))

	fn add_num_box_type(num_type?: webassembly.NumType) -> int:
		let storage_type = webassembly.StorageType.Value(webassembly.ValueType.Num(num_type))
		let field_type = webassembly.FieldType(mutable: true, ty: storage_type)
		let fields: List[webassembly.FieldType] = list1(field_type)
		inject_type(webassembly.CompType.Struct(fields))

	fn add_builtin():
		let params: List[webassembly.ValueType] = List()
		let results: List[webassembly.ValueType] = List()
		params.append(webassembly.ValueType.Ref(webassembly.nullable_ref_type(webassembly.HeapType.TypeIdx(array_i16_type))))  # array
		params.append(webassembly.ValueType.Num(webassembly.NumType.i32()))  # start
		params.append(webassembly.ValueType.Num(webassembly.NumType.i32()))  # end
		results.append(webassembly.ValueType.Ref(ty: webassembly.ref_extern_type()))

		let type_id = inject_type(webassembly.CompType.Func(params, results))

		mk_string_fn_index = func_counter
		imports.append(webassembly.Import(modname: "wasm:js-string", name: "fromCharCodeArray", kind: webassembly.ExternType.Func(typeidx: type_id)))
		func_counter += 1

	pub fn gen_module_defs(modules: List[ast.ModuleDef]) -> webassembly.Module:
		add_i16_array()
		f64_box_type = add_num_box_type(webassembly.NumType.f64())
		f32_box_type = add_num_box_type(webassembly.NumType.f32())
		i64_box_type = add_num_box_type(webassembly.NumType.i64())
		i32_box_type = add_num_box_type(webassembly.NumType.i32())
		add_builtin()

		for module_def in modules:
			log_info("Generating external functions {module_def.get_name()}")
			for definition in module_def.definitions:
				case definition:
					Function(function_def):
						case function_def.body:
							Intern(scoped_block):
								pass
							Extern(libname):
								gen_external_function(function_def)
							None:
								panic("Function declarations not supported")
					Var(var_def):
						case var_def.value:
							Intern(value):
								pass
							Extern(libname, initialized):
								global_mapping.insert(key: var_def.variable.id, value: global_counter)
								global_counter += 1
								let global_ty = get_wasm_type(ty: var_def.variable.ty)
								let kind = webassembly.ExternType.Global(ty: global_ty, mutable: true)
								imports.append(webassembly.Import(modname: libname, name: var_def.variable.id.name, kind))
				else:
					pass

		for module_def in modules:
			for definition in module_def.definitions:
				case definition:
					Function(function_def):
						case function_def.body:
							Intern(scoped_block):
								let key = function_def.name
								index_mapping.insert(key, value: func_counter)
								let name = function_def.name
								# if function_def.is_pub:
								# To use function pointers, functions must be exported, regardless of pub flag.
								exports.append(webassembly.Export(name, kind: webassembly.ExportKind.Func(funcidx: func_counter)))
								func_counter += 1
							Extern(libname):
								pass
							None:
								panic("Function declarations not supported")
					Var(var_def):
						case var_def.value:
							Intern(value):
								global_mapping.insert(key: var_def.variable.id, value: global_counter)
								let name = var_def.variable.id.name
								# if var_def.is_pub:
								exports.append(webassembly.Export(name, kind: webassembly.ExportKind.Global(globalidx: global_counter)))
								global_counter += 1
							Extern(libname, initialized):
								pass
				else:
					pass

		for module_def in modules:
			gen_module(module_def)

		# Tag used for exceptions:
		let typeidx = inject_type(webassembly.CompType.Func(params: list1(webassembly.ValueType.Ref(webassembly.nullable_ref_type(heap_type: webassembly.HeapType.Any()))), results: List()))
		let tags: List[webassembly.Tag] = List()
		imports.append(webassembly.Import(modname: "slangrt", name: "exception_tag", kind: webassembly.ExternType.Tag(typeidx)))

		if not m_string_data.is_empty():
			datas.append(webassembly.Data(data: m_string_data.to_bytes()))

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

		# Kludge to use native popcnt instructions
		if function_def.name == "rt_popcnt" or function_def.name == "rt_ctz" or function_def.name == "rt_clz":
			return

		# Re-export imported function to be able to use it as function pointer
		exports.append(webassembly.Export(name: function_def.name, kind: webassembly.ExportKind.Func(funcidx: func_counter)))
		index_mapping.insert(key: function_def.name, value: func_counter)
		func_counter += 1

		let parameter_types: Vector[ast.Type] = new_vector()
		for parameter in function_def.parameters:
			parameter_types.append(parameter.ty)

		let func_ty = reg_signature(parameter_types, return_type: function_def.info.return_type)
		case function_def.body:
			Extern(libname):
				imports.append(webassembly.Import(modname: libname, name: function_def.name, kind: webassembly.ExternType.Func(typeidx: func_ty)))
		else:
			panic("Invalid extern function")

	fn gen_module(module_def: ast.ModuleDef):
		for definition in module_def.definitions:
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
										mutable: true  # var_def.variable.writable
										ty: get_wasm_type(var_def.variable.ty)
										value: code
									globals.append(g)
								None:
									panic("Uninitialized global")
						Extern(libname, initialized):
							pass
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
			let bits = ty.get_bits()
			let num_type = webassembly.NumType.i64() if bits == 64 else webassembly.NumType.i32()
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
			let bits = ty.get_bits()
			let num_type = webassembly.NumType.f64() if bits == 64 else webassembly.NumType.f32()
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

				if function_def.info.return_type.is_void():
					gen_statement(body, target: Option.None())
				elif function_def.info.return_type.is_unreachable():
					gen_statement(body, target: Option.None())
					# Introduce an unreachable instruction, when we cannot reach this point.
					emit(Instruction.ctrl_unreachable())
				else:
					gen_statement(body, target: Option.Some(function_def.info.return_type))
		else:
			panic("Function without body")

		let f = webassembly.Function:
			typeidx: func_ty
			locals: local_variables
			code
		functions.append(f)

	fn gen_statement(statement?: ast.Statement, target: Option[ast.Type]):
		case statement.kind:
			Break:
				let distance = get_loop()
				emit(Instruction.ctrl_br(distance + 1))
			Continue:
				let distance = get_loop()
				emit(Instruction.ctrl_br(distance))
			Compound(inner):
				let n = inner.len()
				var i = 0
				for sub_statement in inner:
					i += 1
					if i == n:
						gen_statement(sub_statement, target)
					else:
						gen_statement(sub_statement, target: Option.None())
			Expr(expression):
				gen_expression(expression)
				if statement.ty.is_unreachable():
					emit(Instruction.ctrl_unreachable())
			Assignment(target, op, value):
				gen_assignment(target, op, value)
			Let(let_statement):
				gen_expression(let_statement.value)
				let localidx = create_local(id: let_statement.variable.id, ty: let_statement.variable.ty)
				emit(Instruction.local_set(localidx))
			If(if_statement):
				gen_condition(if_statement.condition)
				enter_block(is_loop: false)
				let block_type: webassembly.BlockType = case target:
					None: webassembly.empty_block_type()
					Some(ty): webassembly.one_result_block_type(get_wasm_type(ty))
				emit(Instruction.ctrl_if(block_type))
				gen_statement(if_statement.true_block.body, target)
				emit(Instruction.ctrl_else())
				gen_statement(if_statement.false_block.body, target)
				emit(Instruction.ctrl_end())
				leave_block()
			While(while_statement):
				enter_block(is_loop: true)
				emit(Instruction.ctrl_block(block_type: webassembly.empty_block_type()))
				emit(Instruction.ctrl_loop(block_type: webassembly.empty_block_type()))
				gen_condition(while_statement.condition)
				emit(Instruction.i32_eqz())
				emit(Instruction.ctrl_br_if(1))
				gen_statement(while_statement.block.body, target: Option.None())
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
				gen_try(try_statement)
			Raise(value):
				box_value(value)
				emit(Instruction.ctrl_throw(0))
		else:
			panic("Not implemented: {statement}")

	fn gen_try(try_statement: ast.TryStatement):
		enter_block(is_loop: false)
		emit(Instruction.ctrl_block(block_type: webassembly.empty_block_type()))  # outer block

		enter_block(is_loop: false)
		let exception_type = webassembly.ValueType.Ref(webassembly.nullable_ref_type(webassembly.HeapType.Any()))
		emit(Instruction.ctrl_block(block_type: webassembly.one_result_block_type(exception_type)))  # handler block

		let catchers = list1(webassembly.CatchItem.Catch(tagindex: 0, labelidx: 0))
		enter_block(is_loop: false)
		emit(Instruction.ctrl_try_table(block_type: webassembly.empty_block_type(), catchers))

		gen_statement(try_statement.try_block.body, target: Option.None())
		emit(Instruction.ctrl_end())  # end of try-table
		leave_block()
		emit(Instruction.ctrl_br(1))  # Jump to end of outer, in case of no exception

		emit(Instruction.ctrl_end())  # handler-end
		leave_block()

		# Store exception in variable
		let localidx = create_local(id: try_statement.except_var.id, ty: try_statement.except_var.ty)
		unbox_value(to_type: try_statement.except_var.ty)
		emit(Instruction.local_set(localidx))

		gen_statement(try_statement.except_block.body, target: Option.None())

		emit(Instruction.ctrl_end())  # outer-end
		leave_block()

	fn gen_assignment(target: ast.Expression, op: Option[ast.BinaryOperator], value: ast.Expression):
		case target.kind:
			GetAttr(base, attr):
				let index = ast.get_struct_field_index(ty: base.ty, attr)
				let struct_def = base.ty.get_struct_def()
				let type_index = get_struct_def_index(struct_def)
				gen_expression(base)
				case op:
					Some(op):
						# TODO: would be nice to use dup? wasm does not have it, use a temp local
						let tmp_index = create_anonymous_local(ty: base.ty)
						emit(Instruction.local_set(localidx: tmp_index))
						emit(Instruction.local_get(localidx: tmp_index))
						emit(Instruction.local_get(localidx: tmp_index))

						emit(Instruction.struct_get(ty: type_index, index))
						gen_expression(value)
						gen_op_for_type(op, ty: value.ty)
					None:
						gen_expression(value)
				emit(Instruction.struct_set(ty: type_index, index))
			GetIndex(base, indici):
				assert(condition: indici.len() == 1, message: "Unsupported: multi-index assignment")
				let index = indici.first()
				case op:
					Some(op):
						panic("TODO: base[index] +=")
					None:
						gen_expression(base)
						gen_expression(index)
						emit(Instruction.i32_wrap_i64())  # cast index to 32 bits
						gen_expression(value)
						let type_index = get_array_type_index(element_type: value.ty)
						emit(Instruction.array_set(ty: type_index))
			VariableRef(variable):
				if global_mapping.contains(key: variable.id):
					let globalidx = global_mapping.get(key: variable.id)
					case op:
						Some(op):
							emit(Instruction.global_get(globalidx))
							gen_expression(value)
							gen_op_for_type(op, ty: value.ty)
						None:
							gen_expression(value)
					emit(Instruction.global_set(globalidx))
				else:
					let localidx = get_local_index(id: variable.id)
					case op:
						Some(op):
							emit(Instruction.local_get(localidx))
							gen_expression(value)
							gen_op_for_type(op, ty: value.ty)
						None:
							gen_expression(value)
					emit(Instruction.local_set(localidx))
			ParameterRef(parameter_def):
				let localidx = get_local_index(id: parameter_def.id)
				case op:
					Some(op):
						emit(Instruction.local_get(localidx))
						gen_expression(value)
						gen_op_for_type(op, ty: value.ty)
					None:
						gen_expression(value)
				emit(Instruction.local_set(localidx))
		else:
			panic("Unsupported assignment target: {target}")

	fn gen_op_for_type(op: ast.BinaryOperator, ty: ast.Type):
		if ty.is_int():
			let bits = ty.get_bits()
			let signed = ty.is_signed_int()
			if bits == 64:
				case op:
					Add: emit(Instruction.i64_add())
					Sub: emit(Instruction.i64_sub())
					Mul: emit(Instruction.i64_mul())
					Div: emit(Instruction.i64_div_s() if signed else Instruction.i64_div_u())
				else:
					panic("Invalid 64 bits int binop: {ast.binary_op_to_str(op)}")
			else:
				case op:
					Add: emit(Instruction.i32_add())
					Sub: emit(Instruction.i32_sub())
					Mul: emit(Instruction.i32_mul())
					Div: emit(Instruction.i32_div_s() if signed else Instruction.i32_div_u())
				else:
					panic("Invalid 32 bits int binop: {ast.binary_op_to_str(op)}")
		elif ty.is_float():
			let bits = ty.get_bits()
			if bits == 64:
				case op:
					Add: emit(Instruction.f64_add())
					Sub: emit(Instruction.f64_sub())
					Mul: emit(Instruction.f64_mul())
					Div: emit(Instruction.f64_div())
				else:
					panic("Invalid 64 bits float binop: {ast.binary_op_to_str(op)}")
			else:
				case op:
					Add: emit(Instruction.f32_add())
					Sub: emit(Instruction.f32_sub())
					Mul: emit(Instruction.f32_mul())
					Div: emit(Instruction.f32_div())
				else:
					panic("Invalid 32 bits float binop: {ast.binary_op_to_str(op)}")
		else:
			panic("Unsupported += type: {ty}")

	fn gen_condition(expression?: ast.Expression):
		"""Generate condition, keeping track of short circuit logic."""
		case expression.kind:
			Binop(binop):
				case binop.op:
					And:
						gen_condition(binop.lhs)
						let block_type = webassembly.one_result_block_type(result_type: webassembly.ValueType.Num(num_type: webassembly.NumType.i32()))
						emit(Instruction.ctrl_if(block_type))
						gen_condition(binop.rhs)
						emit(Instruction.ctrl_else())
						emit(Instruction.i32_const(0))
						emit(Instruction.ctrl_end())
					Or:
						gen_condition(binop.lhs)
						let block_type = webassembly.one_result_block_type(result_type: webassembly.ValueType.Num(num_type: webassembly.NumType.i32()))
						emit(Instruction.ctrl_if(block_type))
						emit(Instruction.i32_const(1))
						emit(Instruction.ctrl_else())
						gen_condition(binop.rhs)
						emit(Instruction.ctrl_end())
				else:
					gen_expression(expression)
		else:
			gen_expression(expression)

	fn gen_expression(expression?: ast.Expression):
		case expression.kind:
			IntLiteral(value):
				let bits = expression.ty.get_bits()
				if bits == 64:
					emit(Instruction.i64_const(value))
				else:
					emit(Instruction.i32_const(value))
			BoolLiteral(value):
				emit(Instruction.i32_const(value: 1 if value else 0))
			StringLiteral(value):
				let n = str_len(text: value)
				if n < 4:
					var index = 0
					while index < n:
						let c = str_get(text: value, index)
						emit(Instruction.i32_const(ord(c)))
						index += 1
					emit(Instruction.array_new_fixed(ty: array_i16_type, size: n))
				else:
					let offset = m_string_data.len()
					var index = 0
					while index < n:
						let c = str_get(text: value, index)
						m_string_data.pack_u16_le(ord(c))
						index += 1
					emit(Instruction.i32_const(offset))
					emit(Instruction.i32_const(n))
					emit(Instruction.array_new_data(ty: array_i16_type, dataidx: 0))

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
				emit(Instruction.i32_wrap_i64())  # cast size to 32 bits
				let type_index = get_array_type_index(element_type: ty)
				emit(Instruction.array_new_default(ty: type_index))
			Null:
				emit(Instruction.ref_null(ty: webassembly.HeapType.Any()))
			Binop(binop):
				case binop.op:
					And: gen_condition(expression)
					Or: gen_condition(expression)
				else:
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
				emit(Instruction.i32_wrap_i64())  # cast index to 32 bits
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
				gen_statement(statement, target: Option.Some(expression.ty))
		else:
			panic("Not implemented expression: {expression}")

	fn box_value(value: ast.Expression):
		gen_expression(value)
		if value.ty.is_int():
			let bits = value.ty.get_bits()
			if bits == 64:
				emit(Instruction.struct_new(ty: i64_box_type))
			else:
				emit(Instruction.struct_new(ty: i32_box_type))
		elif value.ty.is_char() or value.ty.is_bool():
			emit(Instruction.ref_i31())
		elif value.ty.is_float():
			let bits = value.ty.get_bits()
			if bits == 64:
				emit(Instruction.struct_new(ty: f64_box_type))
			else:
				emit(Instruction.struct_new(ty: f32_box_type))
		elif value.ty.is_str():
			emit(Instruction.any_convert_extern())
		elif value.ty.is_opaque() or value.ty.is_tycon_app() or value.ty.is_array():
			pass
		else:
			panic("TODO: box of {value.ty}")

	fn unbox_value(to_type: ast.Type):
		if to_type.is_str():
			emit(Instruction.ref_as_non_null())
			emit(Instruction.extern_convert_any())
		elif to_type.is_opaque():
			pass
		elif to_type.is_char() or to_type.is_bool():
			emit(Instruction.ref_cast(webassembly.nullable_ref_type(webassembly.HeapType.i31())))
			emit(Instruction.i31_get(signed: true))
		elif to_type.is_int():
			emit(Instruction.ref_as_non_null())
			let bits = to_type.get_bits()
			if bits == 64:
				emit(Instruction.ref_cast(webassembly.ref_type(webassembly.HeapType.TypeIdx(i64_box_type))))
				emit(Instruction.struct_get(ty: i64_box_type, index: 0))
			else:
				emit(Instruction.ref_cast(webassembly.ref_type(webassembly.HeapType.TypeIdx(i32_box_type))))
				emit(Instruction.struct_get(ty: i32_box_type, index: 0))
		elif to_type.is_float():
			emit(Instruction.ref_as_non_null())
			let bits = to_type.get_bits()
			if bits == 64:
				emit(Instruction.ref_cast(webassembly.ref_type(webassembly.HeapType.TypeIdx(f64_box_type))))
				emit(Instruction.struct_get(ty: f64_box_type, index: 0))
			else:
				emit(Instruction.ref_cast(webassembly.ref_type(webassembly.HeapType.TypeIdx(f32_box_type))))
				emit(Instruction.struct_get(ty: f32_box_type, index: 0))
		elif to_type.is_tycon_app():
			let tycon = to_type.get_tycon()
			case tycon:
				Struct(struct_def):
					let index = get_struct_def_index(struct_def)
					emit(Instruction.ref_cast(webassembly.nullable_ref_type(webassembly.HeapType.TypeIdx(index))))
			else:
				panic("TODO: unbox tycon")
		elif to_type.is_array():
			let index = get_array_type_index(element_type: to_type.get_element_type())
			emit(Instruction.ref_cast(webassembly.nullable_ref_type(webassembly.HeapType.TypeIdx(index))))
		else:
			panic("TODO: unbox to {to_type}")

	fn gen_call(call: ast.FunctionCall):
		case call.callee.kind:
			FunctionRef(function_def, type_arguments):
				for argument in call.arguments:
					gen_expression(argument.value)
				# Kludge for builtin popcnt and clz instructions:
				if function_def.name == "rt_popcnt":
					let bits = call.arguments.first().value.ty.get_bits()
					if bits == 64:
						emit(Instruction.i64_popcnt())
					else:
						emit(Instruction.i32_popcnt())
				elif function_def.name == "rt_ctz":
					let bits = call.arguments.first().value.ty.get_bits()
					if bits == 64:
						emit(Instruction.i64_ctz())
					else:
						emit(Instruction.i32_ctz())
				elif function_def.name == "rt_clz":
					let bits = call.arguments.first().value.ty.get_bits()
					if bits == 64:
						emit(Instruction.i64_clz())
					else:
						emit(Instruction.i32_clz())
				else:
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
			let bits = binop.lhs.ty.get_bits()
			let signed = binop.lhs.ty.is_signed_int()
			if bits == 64:
				case binop.op:
					Add: emit(Instruction.i64_add())
					Sub: emit(Instruction.i64_sub())
					Mul: emit(Instruction.i64_mul())
					Div: emit(Instruction.i64_div_s() if signed else Instruction.i64_div_u())
					Mod: emit(Instruction.i64_rem_s() if signed else Instruction.i64_rem_u())
					Less: emit(Instruction.i64_lt_s() if signed else Instruction.i64_lt_u())
					LessEquals: emit(Instruction.i64_le_s() if signed else Instruction.i64_le_u())
					Greater: emit(Instruction.i64_gt_s() if signed else Instruction.i64_gt_u())
					GreaterEquals: emit(Instruction.i64_ge_s() if signed else Instruction.i64_ge_u())
					Equals: emit(Instruction.i64_eq())
					NotEquals: emit(Instruction.i64_ne())
					BitAnd: emit(Instruction.i64_and())
					BitXor: emit(Instruction.i64_xor())
					BitOr: emit(Instruction.i64_or())
					ShiftLeft: emit(Instruction.i64_shl())
					ShiftRight: emit(Instruction.i64_shr_s() if signed else Instruction.i64_shr_u())
				else:
					panic("Invalid int binop: {ast.binary_op_to_str(binop.op)}")
			else:
				case binop.op:
					Add: emit(Instruction.i32_add())
					Sub: emit(Instruction.i32_sub())
					Mul: emit(Instruction.i32_mul())
					Div: emit(Instruction.i32_div_s() if signed else Instruction.i32_div_u())
					Mod: emit(Instruction.i32_rem_s() if signed else Instruction.i32_rem_u())
					Less: emit(Instruction.i32_lt_s() if signed else Instruction.i32_lt_u())
					LessEquals: emit(Instruction.i32_le_s() if signed else Instruction.i32_le_u())
					Greater: emit(Instruction.i32_gt_s() if signed else Instruction.i32_gt_u())
					GreaterEquals: emit(Instruction.i32_ge_s() if signed else Instruction.i32_ge_u())
					Equals: emit(Instruction.i32_eq())
					NotEquals: emit(Instruction.i32_ne())
					BitAnd: emit(Instruction.i32_and())
					BitXor: emit(Instruction.i32_xor())
					BitOr: emit(Instruction.i32_or())
					ShiftLeft: emit(Instruction.i32_shl())
					ShiftRight: emit(Instruction.i32_shr_s() if signed else Instruction.i32_shr_u())
				else:
					panic("Invalid int binop: {ast.binary_op_to_str(binop.op)}")
		elif binop.lhs.ty.is_bool():
			case binop.op:
				Equals: emit(Instruction.i32_eq())
				NotEquals: emit(Instruction.i32_ne())
			else:
				panic("Invalid bool binop: {ast.binary_op_to_str(binop.op)}")
		elif binop.lhs.ty.is_float():
			let bits = binop.lhs.ty.get_bits()
			if bits == 64:
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
					panic("Invalid f64 binop: {ast.binary_op_to_str(binop.op)}")
			else:
				case binop.op:
					Add: emit(Instruction.f32_add())
					Sub: emit(Instruction.f32_sub())
					Mul: emit(Instruction.f32_mul())
					Div: emit(Instruction.f32_div())
					Less: emit(Instruction.f32_lt())
					LessEquals: emit(Instruction.f32_le())
					Greater: emit(Instruction.f32_gt())
					GreaterEquals: emit(Instruction.f32_ge())
					Equals: emit(Instruction.f32_eq())
					NotEquals: emit(Instruction.f32_ne())
				else:
					panic("Invalid f32 binop: {ast.binary_op_to_str(binop.op)}")
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
				gen_condition(value)
				emit(Instruction.i32_eqz())
			Minus:
				if value.ty.is_int():
					let bits = value.ty.get_bits()
					if bits == 64:
						emit(Instruction.i64_const(0))
						gen_expression(value)
						emit(Instruction.i64_sub())
					else:
						emit(Instruction.i32_const(0))
						gen_expression(value)
						emit(Instruction.i32_sub())
				elif value.ty.is_float():
					gen_expression(value)
					let bits = value.ty.get_bits()
					if bits == 64:
						emit(Instruction.f64_neg())
					else:
						emit(Instruction.f32_neg())
				else:
					panic("unop(-) for {value.ty}")

	fn gen_type_cast(from_type: ast.Type, to_type: ast.Type):
		if to_type.is_float():
			let to_bits = to_type.get_bits()
			if from_type.is_int():
				let from_bits = from_type.get_bits()
				if to_bits == 64:
					if from_bits == 64:
						emit(Instruction.f64_convert_i64_s())
					else:
						emit(Instruction.f64_convert_i32_s())
				else:
					if from_bits == 64:
						emit(Instruction.f32_convert_i64_s())
					else:
						emit(Instruction.f32_convert_i32_s())
			elif from_type.is_float():
				let from_bits = from_type.get_bits()
				if to_bits == 64:
					if from_bits == 64:
						pass  # 64 to 64
					else:
						emit(Instruction.f64_promote_f32())
				else:
					if from_bits == 64:
						emit(Instruction.f32_demote_f64())
					else:
						pass  # 32 to 32
			else:
				panic("TODO: cast {from_type} to float")
		elif to_type.is_int():
			let to_bits = to_type.get_bits()
			let to_signed = to_type.is_signed_int()
			if from_type.is_int():
				let from_bits = from_type.get_bits()
				let from_signed = from_type.is_signed_int()
				if to_bits == 64:
					if from_bits == 64:
						pass  # 64 to 64
					else:
						if from_signed:
							emit(Instruction.i64_extend_i32_s())
						else:
							emit(Instruction.i64_extend_i32_u())
				else:
					if from_bits == 64:
						emit(Instruction.i32_wrap_i64())
					else:
						pass  # 32 to 32
			elif from_type.is_float():
				let from_bits = from_type.get_bits()
				if to_bits == 64:
					if from_bits == 64:
						emit(Instruction.i64_trunc_f64_s())
					else:
						emit(Instruction.i64_trunc_f32_s())
				else:
					if from_bits == 64:
						emit(Instruction.i32_trunc_f64_s())
					else:
						emit(Instruction.i32_trunc_f32_s())
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
		let idx = create_anonymous_local(ty)
		index_mapping.insert(key: ast.node_id_to_string(id), value: idx)
		idx

	fn create_anonymous_local(ty: ast.Type) -> int:
		let idx = local_variables.len() + n_parameters
		let wasm_ty = get_wasm_type(ty)
		local_variables.append(wasm_ty)
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
