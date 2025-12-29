""" Transform BC into SIL

Features of this pass:

- Compile structured types into pointers with load/store operations
- Implement multiply and divide by either physical instructions or a function call to a library

"""

from std import ord
from math import max
from listtype import List, list1
from vectype import Vector, new_vector
from optiontype import Option
from bytes import Bytes, bytes_from_ascii, fill_bytes, ByteArray
from utils import panic, unimplemented
from logging import log_info, log_warning, log_debug
import bc
import vm
import sil

pub struct SilGenOptions:
	""" Target specific options """
	has_div: bool
	has_mul: bool
	has_fpu: bool
	word_size: int

pub fn to_sil(program: bc.Program, bits: int) -> sil.Program:
	# TODO: pass options, su
	log_info("Creating {bits}-bits SIL program from bytecode")
	let g = SilGen(m_bc_program: program, m_bits: bits)
	g.gen_program()

struct StructLayout:
	""" Information how a structure is mapped into memory """
	size: int  # Size of entire struct
	alignment: int
	fields: Vector[StructField]

struct StructField:
	offset: int
	ty: bc.Type

struct TypedValue:
	value: sil.Value
	ty: bc.Type

struct TypedAddress:
	address: sil.Address
	ty: bc.Type

struct ReturnSlot:
	address: TypedAddress
	ty: bc.Type

class SilGen:
	var m_bc_program: bc.Program
	var m_bits: int
	var m_externs: Vector[sil.Extern] = new_vector()
	var m_globals: Vector[TypedAddress] = new_vector()
	var m_structs: Vector[StructLayout] = new_vector()
	var m_functions: Vector[sil.Function] = new_vector()
	var m_blobs: Vector[sil.DataBlob] = new_vector()
	var m_blocks: Vector[sil.Block] = new_vector()
	var m_current_block: Option[sil.Block] = Option.None()
	var m_block_is_terminated: bool = false
	var m_parameters: List[TypedAddress] = List()
	var m_locals: Vector[TypedAddress] = new_vector()
	var m_return_slots: List[ReturnSlot] = List()
	var m_vm: vm.VirtualMachine = vm.VirtualMachine()
	var m_tmp_number: int = 0
	var m_lit_id_number: int = 0
	var m_value_stack: Vector[TypedValue] = new_vector()
	var m_stack_offset: int = 0

	pub fn gen_program() -> sil.Program:
		# Define used runtime functions:
		m_externs.append(sil.Extern(name: "rt_malloc"))
		m_externs.append(sil.Extern(name: "slangrt_box_int64"))
		m_externs.append(sil.Extern(name: "slangrt_box_int32"))
		m_externs.append(sil.Extern(name: "slangrt_box_int16"))
		m_externs.append(sil.Extern(name: "slangrt_box_int8"))
		m_externs.append(sil.Extern(name: "slangrt_box_uint64"))
		m_externs.append(sil.Extern(name: "slangrt_box_uint32"))
		m_externs.append(sil.Extern(name: "slangrt_box_uint16"))
		m_externs.append(sil.Extern(name: "slangrt_box_uint8"))
		m_externs.append(sil.Extern(name: "slangrt_box_char"))
		m_externs.append(sil.Extern(name: "slangrt_box_bool"))
		m_externs.append(sil.Extern(name: "slangrt_box_float64"))
		m_externs.append(sil.Extern(name: "slangrt_box_float32"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_int64"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_int32"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_int16"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_int8"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_uint64"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_uint32"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_uint16"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_uint8"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_char"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_bool"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_float64"))
		m_externs.append(sil.Extern(name: "slangrt_unbox_float32"))

		vm.prepare_vm(vm: m_vm, program: m_bc_program)

		for extern_function in m_bc_program.extern_functions:
			m_externs.append(sil.Extern(name: extern_function.name))

		for struct_def in m_bc_program.structs:
			calc_struct_layout(struct_def)

		for global in m_bc_program.globals:
			gen_global(global)

		for function in m_bc_program.functions:
			gen_function(function)
		sil.Program(externs: m_externs, functions: m_functions, blobs: m_blobs)

	fn gen_global(global: bc.Global):
		let name = global.name
		case global.value:
			Some(code):
				let value = vm.eval_code(vm: m_vm, code)
				let ty = get_sil_type(ty: global.ty)
				let contents = gen_vm_value(ty: global.ty, value)
				m_blobs.append(sil.DataBlob(name, is_local: false, readonly: false, contents))
				let address = sil.Address.Global(name)
				let typed_address = TypedAddress(address, ty: global.ty)
				m_globals.append(typed_address)
			None:
				m_externs.append(sil.Extern(name))
				let address = sil.Address.Global(name)
				let typed_address = TypedAddress(address, ty: global.ty)
				m_globals.append(typed_address)

	fn gen_vm_value(ty: bc.Type, value: vm.Value) -> List[sil.BlobContent]:
		case value:
			Int(value):
				case ty:
					Int(signed, bits):
						# TODO: pack differently when i8?
						let data = pack_i64(value)
						list1(sil.BlobContent.Raw(data))
					Function(parameter_types, return_type):
						let name = get_function_name(index: value)
						list1(sil.BlobContent.Ptr(name))
				else:
					panic("Value must be function or int")
			Bool(b):
				let value = 1 if b else 0
				let data = pack_i64(value)
				list1(sil.BlobContent.Raw(data))
			Float(value):
				let data = case ty:
					Float(bits):
						if bits == 64:
							pack_f64(value)
						elif bits == 32:
							pack_f32(value: float32(value))
						else:
							panic("Unsupported floating point if {bits} bits")
				else:
					panic("Value must be float")
				list1(sil.BlobContent.Raw(data))
			Str(text):
				let data = pack_str(text)
				let name = "_lit_{new_id()}"
				let literal_contents = list1(sil.BlobContent.Raw(data))
				m_blobs.append(sil.DataBlob(name, is_local: true, readonly: true, contents: literal_contents))
				list1(sil.BlobContent.Ptr(name))
			Char(c):
				let data = pack_i64(value: ord(value: c))
				list1(sil.BlobContent.Raw(data))
			List(v):
				let index = case ty:
					StructRef(index):
						index
				else:
					panic("Expect struct type")
				let struct_def = m_bc_program.structs.get(index)
				let contents: List[sil.BlobContent] = List()
				var i = 0
				for field_value in v.values:
					let field_contents = gen_vm_value(ty: struct_def.fields[i].ty, value: field_value)
					contents.extend2(field_contents)
					i += 1
				let name = "_lit_struct_{new_id()}"
				m_blobs.append(sil.DataBlob(name, is_local: true, readonly: false, contents))
				list1(sil.BlobContent.Ptr(name))
			Null:
				panic("TODO: null")
			Undefined:
				panic("TODO: undefined")

	fn calc_struct_layout(struct_def: bc.Struct):
		var alignment = 1
		var offset = 0
		let fields: Vector[StructField] = new_vector()
		for field in struct_def.fields:
			fields.append(StructField(offset, ty: field.ty))
			# TODO: take alignment into account
			let field_size = get_size_of(field.ty)
			offset += field_size
			alignment = max(alignment, field_size)
		m_structs.append(StructLayout(size: offset, alignment, fields))

	fn get_size_of(ty?: bc.Type) -> int:
		case ty:
			Int(signed, bits):
				if bits == 8:
					1
				elif bits == 16:
					2
				elif bits == 32:
					4
				elif bits == 64:
					8
				else:
					panic("Unsupported integer bit size: {bits} bits int type")
			Bool:
				get_word_size()
			Char:
				get_word_size()
			Str:
				get_word_size()
			Ptr:
				get_word_size()
			Float(bits):
				if bits == 32:
					4
				elif bits == 64:
					8
				else:
					panic("Unsupported floating point bit size: {bits}")
			Array(element_type):
				get_word_size()
			StructRef(index):
				get_word_size()
			Function(parameter_types, return_type):
				get_word_size()

	fn get_word_size() -> int:
		if m_bits == 64:
			8
		elif m_bits == 32:
			4
		else:
			panic("Unsupported word size: {m_bits}")

	fn get_ptr_type() -> sil.Type:
		get_word_type()

	fn get_word_type() -> sil.Type:
		if m_bits == 64:
			sil.Type.I64()
		elif m_bits == 32:
			sil.Type.I32()
		else:
			panic("Unsupported word size: {m_bits}")

	fn get_int_type(bits: int) -> sil.Type:
		if bits == 8:
			sil.Type.I8()
		elif bits == 16:
			sil.Type.I16()
		elif bits == 32:
			sil.Type.I32()
		elif bits == 64:
			sil.Type.I64()
		else:
			panic("Unsupported type: {bits} bits int")

	fn get_float_type(bits: int) -> sil.Type:
		if bits == 32:
			sil.Type.F32()
		elif bits == 64:
			sil.Type.F64()
		else:
			panic("Unsupported type: {bits} bits float")

	fn get_sil_type(ty: bc.Type) -> sil.Type:
		case ty:
			Int(signed, bits):
				get_int_type(bits)
			Bool:
				get_word_type()
			Char:
				get_word_type()
			Str:
				get_ptr_type()
			Ptr:
				get_ptr_type()
			Float(bits):
				get_float_type(bits)
			Array(element_type):
				get_ptr_type()
			StructRef(index):
				get_ptr_type()
			Function(parameter_types, return_type):
				get_ptr_type()

	fn gen_function(function: bc.Function):
		log_debug("Gen SIL-code for function {function.name}")
		m_blocks = new_vector()
		m_value_stack.clear()
		m_parameters = List()
		m_locals.clear()
		m_return_slots.clear()
		m_stack_offset = 0
		m_tmp_number = 0
		let start = new_block(name: "start")
		set_current_block(start)

		let parameters: List[sil.Value] = List()
		var index = 1
		while index < function.return_types.len():
			let p = new_tmp(ty: get_ptr_type())
			let ty = bc.Type.Ptr()  # A pointer to whatever type we return
			parameters.append(p)
			let address = new_stack_slot(size: get_size_of(ty))
			emit(op: sil.OpCode.Store(dst: address, value: p))
			m_return_slots.append(ReturnSlot(address: TypedAddress(address, ty), ty: function.return_types.get(index)))
			index += 1

		for parameter in function.parameters:
			let p = new_tmp(ty: get_sil_type(ty: parameter.ty))
			parameters.append(p)
			# Create stack slots for mutable parameters:
			let address = new_stack_slot(size: get_size_of(parameter.ty))
			emit(op: sil.OpCode.Store(dst: address, value: p))
			m_parameters.append(TypedAddress(address, ty: parameter.ty))

		# Create stack slots for mutable locals:
		for local_var in function.locals:
			let address = new_stack_slot(size: get_size_of(local_var.ty))
			m_locals.append(TypedAddress(address, ty: local_var.ty))

		let target_indici = bc.get_target_labels(instructions: function.instructions)
		index = 0
		for opcode in function.instructions:
			if target_indici.contains(index):
				let name = "x_{index}"
				if not m_block_is_terminated:
					emit(sil.OpCode.Jump(name))
				set_current_block(new_block(name))
			gen_opcode(opcode)
			index += 1

		let sil_function = sil.Function(name: function.name, parameters, stacksize: m_stack_offset, start, blocks: m_blocks)
		m_functions.append(sil_function)

	fn gen_opcode(opcode: bc.Instruction):
		# log_info("Gen {bc.instruction_to_string(opcode)}")
		case opcode:
			Nop:
				pass
			Dup:
				let value = pop()
				push(value.value, ty: value.ty)
				push(value.value, ty: value.ty)
			Swap:
				let value1 = pop()
				let value2 = pop()
				push(value1.value, ty: value1.ty)
				push(value2.value, ty: value2.ty)
			Literal(literal):
				case literal:
					Int(value):
						push_int(value)
					Float(value):
						let address = add_f64_blob(value)
						gen_load(address)
					Str(text):
						let data = pack_str(text)
						let literal_address = add_data_blob(data)
						let dst_value = new_tmp(ty: get_ptr_type())
						emit(sil.OpCode.GetAddress(dst_value, literal_address))
						push(dst_value, ty: bc.Type.Str())
					Bool(value):
						if value:
							push_int(1)
						else:
							push_int(0)
					Char(value):
						push_int(ord(value))
					Null:
						push_int(0)
			StructLiteral(index):
				# malloc
				let size = m_structs.get(index).size
				let byte_size_tmp = load_int(value: size)
				call_rt_malloc(size: byte_size_tmp, ty: bc.Type.StructRef(index))
			ArrayLiteral(ty):
				let count_tmp = pop()
				let element_size = get_size_of(ty)
				let element_size_tmp = load_int(value: element_size)
				let byte_size_tmp = new_tmp(ty: get_word_type())
				emit(sil.OpCode.Binop(dst: byte_size_tmp, op2: sil.BinaryOp.Mul(), lhs: count_tmp.value, rhs: element_size_tmp))
				call_rt_malloc(size: byte_size_tmp, ty: bc.Type.Array(ty))
			ToOpaque(ty3):
				let ty = bc.Type.Ptr()
				case ty3:
					Int(signed, bits):
						let value = pop()
						let name = "slangrt_box_int{bits}" if signed else "slangrt_box_uint{bits}"
						call_rt_function_1(name, ty, argument: value.value)
					Float(bits):
						let value = pop()
						let name = "slangrt_box_float{bits}"
						call_rt_function_1(name, ty, argument: value.value)
					Bool:
						let value = pop()
						call_rt_function_1(name: "slangrt_box_bool", ty, argument: value.value)
					Char:
						let value = pop()
						call_rt_function_1(name: "slangrt_box_char", ty, argument: value.value)
					Ptr:
						pass
					Str:
						let value = pop()
						push(value.value, ty)
					StructRef(index):
						let value = pop()
						push(value.value, ty)
					Function(parameter_types, return_type):
						panic("Cannot box function")
					Array(element_type):
						let value = pop()
						push(value.value, ty)
			FromOpaque(ty):
				case ty:
					Int(signed, bits):
						let value = pop()
						let name = "slangrt_unbox_int{bits}" if signed else "slangrt_unbox_uint{bits}"
						call_rt_function_1(name, ty, argument: value.value)
					Float(bits):
						let value = pop()
						let name = "slangrt_unbox_float{bits}"
						call_rt_function_1(name, ty, argument: value.value)
					Char:
						let value = pop()
						call_rt_function_1(name: "slangrt_unbox_char", ty, argument: value.value)
					Bool:
						let value = pop()
						call_rt_function_1(name: "slangrt_unbox_bool", ty, argument: value.value)
					Ptr:
						pass
					Function(parameter_types, return_type):
						panic("Cannot unbox ptr to function")
					Str:
						let value = pop()
						push(value.value, ty)
					StructRef(index):
						let value = pop()
						push(value.value, ty)
					Array(element_type):
						let value = pop()
						push(value.value, ty)
			Binop(op):
				let rhs = pop()
				let lhs = pop()
				let op2 = case op:
					Add:
						sil.BinaryOp.Add()
					Sub:
						sil.BinaryOp.Sub()
					Divide:
						sil.BinaryOp.Div()
					Modulo:
						sil.BinaryOp.Mod()
					Multiply:
						sil.BinaryOp.Mul()
				let dst = new_tmp(ty: lhs.value.ty)
				push(dst, ty: lhs.ty)
				emit(sil.OpCode.Binop(dst, op2, lhs: lhs.value, rhs: rhs.value))
			GlobalGet(index):
				let address = m_globals.get(index)
				gen_load(address)
			GlobalSet(index):
				let address = m_globals.get(index)
				let value = pop()
				gen_store(address, value)
			LocalGet(index):
				let address = m_locals[index]
				gen_load(address)
			LocalSet(index):
				let address = m_locals[index]
				let value = pop()
				gen_store(address, value)
			ParameterGet(index):
				let address = m_parameters[index]
				gen_load(address)
			ParameterSet(index):
				let address = m_parameters[index]
				let value = pop()
				gen_store(address, value)
			GetIndex:
				let index = pop()
				let base = pop()
				let address = gen_element_address(base, index)
				gen_load(address)
			SetIndex:
				let value = pop()
				let index = pop()
				let base = pop()
				let address = gen_element_address(base, index)
				gen_store(address, value)
			GetAttr(index):
				let base = pop()
				let address = gen_struct_address(base, index)
				gen_load(address)
			SetAttr(index):
				let value = pop()
				let base = pop()
				let address = gen_struct_address(base, index)
				gen_store(address, value)
			JumpIf(op, label1, label2):
				let rhs = pop()
				let lhs = pop()
				let op2 = case op:
					Greater:
						sil.CompOp.Gt()
					Less:
						sil.CompOp.Lt()
					GreaterEquals:
						sil.CompOp.Gte()
					LessEquals:
						sil.CompOp.Lte()
					Equals:
						sil.CompOp.Eq()
					NotEquals:
						sil.CompOp.Neq()
				emit(sil.OpCode.JumpIf(lhs: lhs.value, op: op2, rhs: rhs.value, label1: "x_{label1}", label2: "x_{label2}"))
			Jump(label):
				emit(sil.OpCode.Jump(label: "x_{label}"))
			Call(index):
				let n = 2
				if index < m_bc_program.extern_functions.len():
					let function = m_bc_program.extern_functions[index]
					let callee = new_global(function.name)
					gen_call(callee, n_args: function.parameters.len(), return_types: function.return_types)
				else:
					index = index - m_bc_program.extern_functions.len()
					let function = m_bc_program.functions[index]
					let callee = new_global(function.name)
					gen_call(callee, n_args: function.parameters.len(), return_types: function.return_types)
			CallIndirect(parameter_types, return_types):
				let target = pop()
				let callee = sil.Address.Ptr(addr: target.value)
				gen_call(callee, n_args: parameter_types.len(), return_types)
			Return(v):
				if v == 0:
					emit(sil.OpCode.Return(value: Option.None()))
				else:
					if v > 1:
						let values = pop_n_typed(count: v - 1)
						var index = 0
						for value in values:
							let return_slot = m_return_slots.get(index)  # Pointer to pointer to return value
							let ret_ptr = new_tmp(ty: get_ptr_type())
							emit(sil.OpCode.Load(dst: ret_ptr, address: return_slot.address.address))
							let address = TypedAddress(address: sil.Address.Ptr(addr: ret_ptr), ty: return_slot.ty)
							gen_store(address, value)
							index += 1
					let value = pop()
					emit(sil.OpCode.Return(value: Option.Some(value.value)))
			Unreachable:
				emit(sil.OpCode.Halt())
			IntToFloat(bits):
				let dst = new_tmp(ty: get_float_type(bits))
				let value = pop()
				emit(sil.OpCode.Convert(signed: true, dst, value: value.value))
				push(dst, ty: bc.Type.Float(bits))
			FloatToInt(signed, bits):
				let dst = new_tmp(ty: get_int_type(bits))
				let value = pop()
				emit(sil.OpCode.Convert(signed: true, dst, value: value.value))
				push(dst, ty: bc.Type.Int(signed: true, bits))
			IntCast(signed, bits):
				let dst = new_tmp(ty: get_int_type(bits))
				let value = pop()
				let src_is_signed = case value.ty:
					Int(signed, bits):
						signed
				else:
					panic("Invalid type for int cast")
				emit(sil.OpCode.Convert(signed: src_is_signed, dst, value: value.value))
				push(dst, ty: bc.Type.Int(signed, bits))
			FloatCast(bits):
				let dst = new_tmp(ty: get_float_type(bits))
				let value = pop()
				emit(sil.OpCode.Convert(signed: true, dst, value: value.value))
				push(dst, ty: bc.Type.Float(bits))
			Not:
				# Xor with 1, to toggle boolean value.
				let value = pop()
				let one = load_int(value: 1)
				let dst = new_tmp(ty: get_word_type())
				emit(sil.OpCode.Bitop(dst, op: sil.BitwiseOp.Xor(), lhs: value.value, rhs: one))
				push(dst, ty: bc.Type.Int(signed: true, bits: 64))
			Neg:
				let value = pop()
				case value.ty:
					Int(signed, bits):
						let zero = load_int(value: 0)
						let dst = new_tmp(ty: get_int_type(bits))
						emit(sil.OpCode.Binop(dst, op: sil.BinaryOp.Sub(), lhs: zero, rhs: value.value))
						push(dst, ty: bc.Type.Int(signed, bits))
					Float(bits):
						let address = add_f64_blob(value: 0.0)
						gen_load(address)
						let zero = pop()
						let dst = new_tmp(ty: get_float_type(bits))
						emit(sil.OpCode.Binop(dst, op: sil.BinaryOp.Sub(), lhs: zero.value, rhs: value.value))
						push(dst, ty: bc.Type.Float(bits))
				else:
					unimplemented("NEG for {bc.type_to_string(value.ty)}")
			Bitop(op):
				let rhs = pop()
				let lhs = pop()
				let op2 = case op:
					And:
						sil.BitwiseOp.And()
					Or:
						sil.BitwiseOp.Or()
					Xor:
						sil.BitwiseOp.Xor()
					Shr:
						sil.BitwiseOp.Shr()
					Shl:
						sil.BitwiseOp.Shl()
				let dst = new_tmp(ty: lhs.value.ty)
				push(dst, ty: lhs.ty)
				emit(sil.OpCode.Bitop(dst, op2, lhs: lhs.value, rhs: rhs.value))
			DecRef(index):
				log_warning("Dec ref implemented as no-op")
			LoadFunc(index):
				let name = get_function_name(index)
				let address = new_global(name)
				let dst_value = new_tmp(ty: get_ptr_type())
				emit(sil.OpCode.GetAddress(dst_value, address))
				push(dst_value, ty: bc.Type.Ptr())

	fn get_function_name(index: int) -> str:
		if index < m_bc_program.extern_functions.len():
			let function = m_bc_program.extern_functions.get(index)
			function.name
		else:
			index = index - m_bc_program.extern_functions.len()
			let function = m_bc_program.functions.get(index)
			function.name

	fn gen_load(address: TypedAddress):
		""" Load value from address """
		let value = new_tmp(ty: get_sil_type(ty: address.ty))
		emit(sil.OpCode.Load(dst: value, address: address.address))
		push(value, ty: address.ty)

	fn gen_store(address: TypedAddress, value: TypedValue):
		emit(sil.OpCode.Store(address: address.address, value: value.value))

	fn gen_element_address(base: TypedValue, index: TypedValue) -> TypedAddress:
		""" base + index * sizeof """
		let element_ty = case base.ty:
			Array(element_ty):
				element_ty
		else:
			panic("Cannot get element address of non array type")
		let element_size = get_size_of(element_ty)
		let offset = new_tmp(ty: get_word_type())
		let addr = new_tmp(ty: get_ptr_type())
		let size_of = load_int(value: element_size)
		emit(sil.OpCode.Binop(dst: offset, op: sil.BinaryOp.Mul(), lhs: index.value, rhs: size_of))
		emit(sil.OpCode.Binop(dst: addr, op: sil.BinaryOp.Add(), lhs: base.value, rhs: offset))
		TypedAddress(address: sil.Address.Ptr(addr), ty: element_ty)

	fn gen_struct_address(base: TypedValue, index: int) -> TypedAddress:
		let struct_index = case base.ty:
			StructRef(index):
				index
		else:
			panic("Cannot get struct field address of non struct type")
		let struct_layout = m_structs.get(index: struct_index)
		let field = struct_layout.fields.get(index)
		let offset = load_int(value: field.offset)
		let addr = new_tmp(ty: get_ptr_type())
		emit(sil.OpCode.Binop(dst: addr, op: sil.BinaryOp.Add(), lhs: base.value, rhs: offset))
		TypedAddress(address: sil.Address.Ptr(addr), ty: field.ty)

	fn gen_call(callee: sil.Address, n_args: int, return_types: Vector[bc.Type]):
		let arguments = pop_n(count: n_args)

		if return_types.is_empty():
			emit(sil.OpCode.Call(Option.None(), callee, arguments))
		else:
			let new_arguments: List[sil.Value] = List()
			let ty = return_types.get(index: 0)
			let value = new_tmp(ty: get_sil_type(ty))
			if return_types.len() > 1:
				var index = 1
				let extra_values: List[TypedAddress] = List()
				while index < return_types.len():
					let rty = return_types.get(index)
					let address = new_stack_slot(size: get_size_of(rty))
					extra_values.append(TypedAddress(address, ty: rty))
					let ret_ptr = new_tmp(ty: get_ptr_type())
					emit(sil.OpCode.GetAddress(dst: ret_ptr, address))
					new_arguments.append(ret_ptr)
					index += 1
				new_arguments.extend2(arguments)

				emit(sil.OpCode.Call(Option.Some(value), callee, arguments: new_arguments))
				push(value, ty)
				for address in extra_values:
					gen_load(address)
			else:
				emit(sil.OpCode.Call(Option.Some(value), callee, arguments))
				push(value, ty)

	fn call_rt_malloc(size: sil.Value, ty: bc.Type):
		call_rt_function_1(name: "rt_malloc", ty, argument: size)

	fn call_rt_function_1(name: str, ty: bc.Type, argument: sil.Value):
		let arguments: List[sil.Value] = List()
		arguments.append(argument)
		call_rt_function(name, ty, arguments)

	fn call_rt_function(name: str, ty: bc.Type, arguments: List[sil.Value]):
		""" Invoke runtime helper function """
		let callee = sil.Address.Global(name)
		let value = new_tmp(ty: get_sil_type(ty))
		emit(sil.OpCode.Call(Option.Some(value), callee, arguments))
		push(value, ty)

	fn load_int(value: int) -> sil.Value:
		let dst = new_tmp(ty: get_word_type())
		emit(sil.OpCode.Const(dst, value))
		dst

	fn new_block(name: str) -> sil.Block:
		let instructions: Vector[sil.Instruction] = new_vector()
		let block = sil.Block(name, instructions)
		m_blocks.append(block)
		block

	fn new_tmp(ty: sil.Type) -> sil.Value:
		sil.Value(id: new_tmp_id(), ty)

	fn new_stack_slot(size: int) -> sil.Address:
		let offset = m_stack_offset
		m_stack_offset += size
		sil.Address.StackSlot(offset)

	fn new_tmp_id() -> int:
		let id = m_tmp_number
		m_tmp_number += 1
		id

	fn new_id() -> int:
		m_lit_id_number += 1
		m_lit_id_number

	fn new_global(name?: str) -> sil.Address:
		sil.Address.Global(name)

	fn add_f64_blob(value: float) -> TypedAddress:
		let data = pack_f64(value)
		let blob_address = add_data_blob(data)
		let ty = bc.Type.Float(bits: 64)
		TypedAddress(address: blob_address, ty)

	fn add_data_blob(data?: Bytes) -> sil.Address:
		# TODO: we have a chance to deduplicate blobs here!
		let name = "lit_{new_id()}"
		let contents = list1(sil.BlobContent.Raw(data))
		m_blobs.append(sil.DataBlob(name, is_local: true, readonly: true, contents))
		sil.Address.Global(name)

	fn push_int(value?: int):
		let dst = load_int(value)
		push(dst, ty: bc.Type.Int(signed: true, bits: 64))

	fn push(value?: sil.Value, ty: bc.Type):
		m_value_stack.append(TypedValue(value, ty))

	fn pop() -> TypedValue:
		m_value_stack.pop_last()

	fn pop_n(count: int) -> List[sil.Value]:
		let values: List[sil.Value] = List()
		while values.len() < count:
			let val = pop()
			values.prepend(val.value)
		values

	fn pop_n_typed(count: int) -> List[TypedValue]:
		let values: List[TypedValue] = List()
		while values.len() < count:
			values.prepend(pop())
		values

	fn set_current_block(block?: sil.Block):
		m_current_block = Option.Some(block)
		m_block_is_terminated = false

	fn emit(op?: sil.OpCode):
		case m_current_block:
			Some(block):
				let instruction = sil.Instruction(op)
				# print("> {instruction}")
				if m_block_is_terminated:
					# panic("Block already terminated!")
					pass
				else:
					if sil.is_terminating_op(op):
						m_block_is_terminated = true
				block.instructions.append(instruction)
			None:
				panic("Cannot emit")

fn pack_f64(value: float64) -> Bytes:
	""" Place 64 bits float into 8 bytes """
	let ba = ByteArray()
	ba.pack_f64_le(value)
	ba.to_bytes()

fn pack_f32(value: float32) -> Bytes:
	""" Place 32 bits float into 4 bytes """
	let ba = ByteArray()
	ba.pack_f32_le(value)
	ba.to_bytes()

fn pack_i64(value: int) -> Bytes:
	""" Place 64 bits integer into 8 bytes """
	let ba = ByteArray()
	ba.pack_u64_le(value)
	ba.to_bytes()

fn pack_str(text: str) -> Bytes:
	bytes_from_ascii(text).concat(other: fill_bytes(n: 1, fill: 0))
