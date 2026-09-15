module compiler.bc_to_sil
"""Transform BC into SIL

Features of this pass:

- Compile structured types into pointers with load/store operations
- Implement multiply and divide by either physical instructions or a function call to a library
"""

from std import ord, print
from base.math import max
from base.listtype import List, list1
from base.vectype import Vector, new_vector, new_vector_with_capacity, vec1, vec2, vec3
from base.optiontype import Option
from base.bytes import Bytes, bytes_from_ascii, fill_bytes, ByteArray
from base.utils import panic, unimplemented
from base.logging import log_info, log_warning, log_debug
import bc
import vm
import sil

# TODO: de-duplicate with c_gen code?
fn is_heap(ty?: bc.Type) -> bool:
	"""Test if type is heap like type"""
	case ty:
		StructRef(index): true
		Array(element_type): true
		Str: true
		Ptr: true
	else:
		false

pub struct SilGenOptions:
	"""Target specific options"""
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
	"""Information how a structure is mapped into memory"""
	size: int  # Size of entire struct
	alignment: int
	fields: Vector[StructField]
	gc_info: Option[sil.Address]  # optional array with gc info

struct StructField:
	offset: int
	ty: bc.Type

struct TypedValue:
	value: sil.Value
	ty: bc.Type
	owned: bool

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
		m_externs.append(sil.Extern(name: "rt_str_new"))
		m_externs.append(sil.Extern(name: "rt_malloc_struct"))
		m_externs.append(sil.Extern(name: "rt_malloc_array"))
		m_externs.append(sil.Extern(name: "rt_inc_ref"))
		m_externs.append(sil.Extern(name: "rt_dec_ref"))
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
				let address = sil.Address.Global(name, mutable: true)
				let typed_address = TypedAddress(address, ty: global.ty)
				if is_heap(ty: global.ty):
					# Initialize with NULL:
					let data = pack_i64(value: 0)
					let contents = list1(sil.BlobContent.Raw(data))
					m_blobs.append(sil.DataBlob(name, is_local: false, readonly: false, contents))

					# Create init code:
					begin_func()
					let start = new_block(name: "start")
					set_current_block(start)

					# Assume straight line code here:
					for opcode in code:
						gen_opcode(opcode)
					gen_store(address: typed_address, value: pop())

					let init_func_name = "_init_func_{name}"
					# add constructor 109 tag
					let parameters: Vector[sil.Value] = new_vector()
					let sil_function = sil.Function(name: init_func_name, parameters, stacksize: m_stack_offset, start, blocks: m_blocks, is_constructor: true)
					m_functions.append(sil_function)

					# TODO: add destructor as well?
				else:
					let value = vm.eval_code(vm: m_vm, code)
					let contents = gen_vm_value(ty: global.ty, value)
					m_blobs.append(sil.DataBlob(name, is_local: false, readonly: false, contents))
				m_globals.append(typed_address)
			None:
				m_externs.append(sil.Extern(name))
				let address = sil.Address.Global(name, mutable: true)
				let typed_address = TypedAddress(address, ty: global.ty)
				m_globals.append(typed_address)

	fn gen_vm_value(ty: bc.Type, value: vm.Value) -> List[sil.BlobContent]:
		case value:
			Int64(value):
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
			Int32(value):
				case ty:
					Int(signed, bits):
						# TODO: pack differently when i8?
						let data = pack_i32(value)
						list1(sil.BlobContent.Raw(data))
				else:
					panic("Value must be function or int")
			Int16(value):
				case ty:
					Int(signed, bits):
						# TODO: pack differently when i8?
						let data = pack_i16(value)
						list1(sil.BlobContent.Raw(data))
				else:
					panic("Value must be function or int")
			Int8(value):
				case ty:
					Int(signed, bits):
						# TODO: pack differently when i8?
						let data = pack_i8(value)
						list1(sil.BlobContent.Raw(data))
				else:
					panic("Value must be function or int")
			Uint64(value):
				case ty:
					Int(signed, bits):
						# TODO: pack differently when i8?
						let data = pack_u64(value)
						list1(sil.BlobContent.Raw(data))
				else:
					panic("Value must be function or int")
			Uint32(value):
				case ty:
					Int(signed, bits):
						# TODO: pack differently when i8?
						let data = pack_u32(value)
						list1(sil.BlobContent.Raw(data))
				else:
					panic("Value must be function or int")
			Uint16(value):
				case ty:
					Int(signed, bits):
						# TODO: pack differently when i8?
						let data = pack_u16(value)
						list1(sil.BlobContent.Raw(data))
				else:
					panic("Value must be function or int")
			Uint8(value):
				case ty:
					Int(signed, bits):
						# TODO: pack differently when i8?
						let data = pack_u8(value)
						list1(sil.BlobContent.Raw(data))
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
				panic("Cannot create global string")
			Char(c):
				let data = pack_i64(value: ord(value: c))
				list1(sil.BlobContent.Raw(data))
			List(v):
				panic("Cannot create global struct literal")
			Null:
				panic("TODO: null")
			Undefined:
				panic("TODO: undefined")

	fn calc_struct_layout(struct_def: bc.Struct):
		var alignment = 1
		var offset = 0
		let fields: Vector[StructField] = new_vector_with_capacity(capacity: struct_def.fields.len())
		let ptr_offsets: List[int] = List()
		for field in struct_def.fields:
			fields.append(StructField(offset, ty: field.ty))
			if is_heap(field.ty):
				ptr_offsets.append(offset)
			# TODO: take alignment into account
			let field_size = get_size_of(field.ty)
			offset += field_size
			alignment = max(alignment, field_size)

		# Create GC information:
		let gc_info = if ptr_offsets.is_empty():
			Option.None()
		else:
			# Emit literal with pointer offsets
			let blob = List()
			ptr_offsets.append(-1)  # Terminator
			let contents: List[sil.BlobContent] = List()
			for ptr_offset in ptr_offsets:
				# int = 4 bytes on 64 bit, hence pack as i32
				contents.append(sil.BlobContent.Raw(pack_i32(value: int32(ptr_offset))))
			let name = "_lit_struct_gc_info_{new_id()}"
			m_blobs.append(sil.DataBlob(name, is_local: true, readonly: false, contents))
			Option.Some(sil.Address.Global(name, mutable: false))
		m_structs.append(StructLayout(size: offset, alignment, fields, gc_info))

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
			Bool: get_word_size()
			Char: get_word_size()
			Str: get_word_size()
			Ptr: get_word_size()
			FuncPtr: get_word_size()
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
			FuncPtr:
				get_ptr_type()
			Float(bits):
				get_float_type(bits)
			Array(element_type):
				get_ptr_type()
			StructRef(index):
				get_ptr_type()
			Function(parameter_types, return_type):
				get_ptr_type()

	fn begin_func():
		m_blocks = new_vector()
		m_value_stack.clear()
		m_parameters = List()
		m_locals.clear()
		m_return_slots.clear()
		m_stack_offset = 0
		m_tmp_number = 0

	fn gen_function(function: bc.Function):
		log_debug("Gen SIL-code for function {function.name}")
		begin_func()
		let start = new_block(name: "start")
		set_current_block(start)

		let parameters: Vector[sil.Value] = new_vector()
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
			let typed_address = TypedAddress(address, ty: local_var.ty)
			m_locals.append(typed_address)
			if is_heap(local_var.ty):
				gen_store(address: typed_address, value: load_null_ptr())

		let target_indici = bc.get_target_labels(instructions: function.instructions)
		index = 0
		for opcode in function.instructions:
			let bc_label = uint32(index)
			if target_indici.contains(bc_label):
				let name = make_label(bc_label)
				if not m_block_is_terminated:
					emit(sil.OpCode.Jump(name))
				set_current_block(new_block(name))
			gen_opcode(opcode)
			index += 1

		let sil_function = sil.Function(name: function.name, parameters, stacksize: m_stack_offset, start, blocks: m_blocks, is_constructor: false)
		m_functions.append(sil_function)

	fn make_label(x?: uint32) -> str:
		"x_{int(x)}"

	fn gen_opcode(opcode: bc.Instruction):
		# log_info("Gen {bc.instruction_to_string(opcode)}")
		case opcode:
			Nop:
				pass
			Dup:
				let value = pop()
				push(value.value, ty: value.ty, owned: value.owned)
				push(value.value, ty: value.ty, owned: false)
			Swap:
				let value1 = pop()
				let value2 = pop()
				push(value1.value, ty: value1.ty, owned: value1.owned)
				push(value2.value, ty: value2.ty, owned: value2.owned)
			Literal(literal):
				case literal:
					Int(value):
						push_int(value)
					Float(value):
						let address = add_f64_blob(value)
						gen_load(address, owned: false)
					Str(text):
						let data = pack_str(text)
						let literal_address = add_data_blob(data)
						let dst_value = new_tmp(ty: get_ptr_type())
						emit(sil.OpCode.GetAddress(dst_value, literal_address))
						call_rt_function_1(name: "rt_str_new", ty: bc.Type.Str(), argument: dst_value)
					Bool(value):
						push_int(1 if value else 0)
					Char(value):
						push_int(ord(value))
					Null:
						push_int(0)
			StructLiteral(index):
				let info = m_structs.get(index)
				let size = info.size
				let byte_size_tmp = load_int(value: size)
				let type_info_ptr = case info.gc_info:
					None:
						load_int(value: 0)
					Some(literal_address):
						let dst_value = new_tmp(ty: get_ptr_type())
						emit(sil.OpCode.GetAddress(dst_value, literal_address))
						dst_value
				call_rt_function(name: "rt_malloc_struct", ty: bc.Type.StructRef(index), arguments: vec2(byte_size_tmp, type_info_ptr))
			ArrayLiteral(ty):
				let count_tmp = pop()
				let element_size = get_size_of(ty)
				let element_size_tmp = load_int(value: element_size)
				let elements_are_pointers = load_int(value: 1 if is_heap(ty) else 0)
				call_rt_function(name: "rt_malloc_array", ty: bc.Type.Array(ty), arguments: vec3(count_tmp.value, element_size_tmp, elements_are_pointers))
			ToOpaque(ty3):
				let ty = bc.Type.Ptr()
				let value = pop()
				case ty3:
					Int(signed, bits):
						let name = "slangrt_box_int{bits}" if signed else "slangrt_box_uint{bits}"
						call_rt_function_1(name, ty, argument: value.value)
					Float(bits):
						let name = "slangrt_box_float{bits}"
						call_rt_function_1(name, ty, argument: value.value)
					Bool:
						call_rt_function_1(name: "slangrt_box_bool", ty, argument: value.value)
					Char:
						call_rt_function_1(name: "slangrt_box_char", ty, argument: value.value)
					Ptr:
						push(value.value, ty, owned: value.owned)
					FuncPtr:
						panic("Cannot box function pointer")
					Str:
						push(value.value, ty, owned: value.owned)
					StructRef(index):
						push(value.value, ty, owned: value.owned)
					Function(parameter_types, return_type):
						panic("Cannot box function")
					Array(element_type):
						push(value.value, ty, owned: value.owned)
			FromOpaque(ty):
				let value = pop()
				case ty:
					Int(signed, bits):
						let name = "slangrt_unbox_int{bits}" if signed else "slangrt_unbox_uint{bits}"
						call_rt_function_1(name, ty, argument: value.value)
						drop(value)
					Float(bits):
						let name = "slangrt_unbox_float{bits}"
						call_rt_function_1(name, ty, argument: value.value)
						drop(value)
					Char:
						call_rt_function_1(name: "slangrt_unbox_char", ty, argument: value.value)
						drop(value)
					Bool:
						call_rt_function_1(name: "slangrt_unbox_bool", ty, argument: value.value)
						drop(value)
					Ptr:
						push(value.value, ty, owned: value.owned)
					FuncPtr:
						panic("Cannot unbox ptr to function pointer")
					Function(parameter_types, return_type):
						panic("Cannot unbox ptr to function")
					Str:
						push(value.value, ty, owned: value.owned)
					StructRef(index):
						push(value.value, ty, owned: value.owned)
					Array(element_type):
						push(value.value, ty, owned: value.owned)
			Binop(op, ty):
				let rhs = pop()
				let lhs = pop()
				let op2 = case op:
					Add: sil.BinaryOp.Add()
					Sub: sil.BinaryOp.Sub()
					Divide: sil.BinaryOp.Div()
					Modulo: sil.BinaryOp.Mod()
					Multiply: sil.BinaryOp.Mul()
				let dst = new_tmp(ty: lhs.value.ty)
				push(dst, ty: lhs.ty, owned: false)
				emit(sil.OpCode.Binop(dst, op2, lhs: lhs.value, rhs: rhs.value))
			GlobalGet(index):
				let address = m_globals.get(index)
				gen_load(address, owned: false)
			GlobalSet(index):
				let address = m_globals.get(index)
				let value = pop()
				if is_heap(address.ty):
					transfer_to_owned(address, value)
				gen_store(address, value)
			LocalGet(index):
				let address = m_locals[index]
				gen_load(address, owned: false)
			LocalSet(index):
				let value = pop()
				let address = m_locals[index]
				if is_heap(value.ty):
					transfer_to_owned(address, value)
				gen_store(address, value)
			ParameterGet(index):
				let address = m_parameters[index]
				gen_load(address, owned: false)
			ParameterSet(index):
				let address = m_parameters[index]
				if is_heap(address.ty):
					panic("Cannot write to heap typed parameters")
				let value = pop()
				gen_store(address, value)
			GetIndex:
				let index = pop()
				let base = pop()
				let address = gen_element_address(base, index)
				gen_load(address, owned: false)
			SetIndex:
				let value = pop()
				let index = pop()
				let base = pop()
				let address = gen_element_address(base, index)
				if is_heap(value.ty):
					transfer_to_owned(address, value)
				gen_store(address, value)
				drop(base)
			GetAttr(index):
				let base = pop()
				let address = gen_struct_address(base, index)
				var owned = false
				if is_heap(address.ty) and base.owned:
					owned = true
				gen_load(address, owned)
				if owned:
					inc_ref(m_value_stack.last())
				drop(base)
			SetAttr(index):
				let value = pop()
				let base = pop()
				let address = gen_struct_address(base, index)
				if is_heap(value.ty):
					transfer_to_owned(address, value)
				gen_store(address, value)
				drop(base)
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
				emit(sil.OpCode.JumpIf(lhs: lhs.value, op: op2, rhs: rhs.value, label1: make_label(label1), label2: make_label(label2)))
			Jump(label):
				emit(sil.OpCode.Jump(label: make_label(label)))
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
				let optional_value: Option[sil.Value] = if v == 0:
					Option.None()
				else:
					if v > 1:
						let values = pop_n(count: v - 1)
						var index = 0
						for value in values:
							if not value.owned:
								inc_ref(value)
							let return_slot = m_return_slots.get(index)  # Pointer to pointer to return value
							let ret_ptr = new_tmp(ty: get_ptr_type())
							emit(sil.OpCode.Load(dst: ret_ptr, address: return_slot.address.address))
							let address = TypedAddress(address: sil.Address.Ptr(addr: ret_ptr), ty: return_slot.ty)
							gen_store(address, value)
							index += 1
					let value = pop()
					if not value.owned:
						inc_ref(value)
					Option.Some(value.value)

				# Decrease references of local variables:
				for local_var in m_locals:
					if is_heap(local_var.ty):
						gen_load(address: local_var, owned: true)
						dec_ref(pop())
				emit(sil.OpCode.Return(value: optional_value))
			Unreachable:
				emit(sil.OpCode.Halt())
			IntToFloat(bits):
				let dst = new_tmp(ty: get_float_type(bits))
				let value = pop()
				emit(sil.OpCode.Convert(signed: true, dst, value: value.value))
				push(dst, ty: bc.Type.Float(bits), owned: false)
			FloatToInt(signed, bits):
				let dst = new_tmp(ty: get_int_type(bits))
				let value = pop()
				emit(sil.OpCode.Convert(signed: true, dst, value: value.value))
				push(dst, ty: bc.Type.Int(signed: true, bits), owned: false)
			IntCast(signed, bits):
				let dst = new_tmp(ty: get_int_type(bits))
				let value = pop()
				let src_is_signed = case value.ty:
					Int(signed, bits):
						signed
				else:
					panic("Invalid type for int cast")
				emit(sil.OpCode.Convert(signed: src_is_signed, dst, value: value.value))
				push(dst, ty: bc.Type.Int(signed, bits), owned: false)
			FloatCast(bits):
				let dst = new_tmp(ty: get_float_type(bits))
				let value = pop()
				emit(sil.OpCode.Convert(signed: true, dst, value: value.value))
				push(dst, ty: bc.Type.Float(bits), owned: false)
			Not:
				# Xor with 1, to toggle boolean value.
				let value = pop()
				let one = load_int(value: 1)
				let dst = new_tmp(ty: get_word_type())
				emit(sil.OpCode.Bitop(dst, op: sil.BitwiseOp.Xor(), lhs: value.value, rhs: one))
				push(dst, ty: bc.Type.Int(signed: true, bits: 64), owned: false)
			Neg:
				let value = pop()
				case value.ty:
					Int(signed, bits):
						let zero = load_int(value: 0)
						let dst = new_tmp(ty: get_int_type(bits))
						emit(sil.OpCode.Binop(dst, op: sil.BinaryOp.Sub(), lhs: zero, rhs: value.value))
						push(dst, ty: bc.Type.Int(signed, bits), owned: false)
					Float(bits):
						let address = add_f64_blob(value: 0.0)
						gen_load(address, owned: false)
						let zero = pop()
						let dst = new_tmp(ty: get_float_type(bits))
						emit(sil.OpCode.Binop(dst, op: sil.BinaryOp.Sub(), lhs: zero.value, rhs: value.value))
						push(dst, ty: bc.Type.Float(bits), owned: false)
				else:
					unimplemented("NEG for {bc.type_to_string(value.ty)}")
			Bitop(op, ty):
				let rhs = pop()
				let lhs = pop()
				let op2 = case op:
					And: sil.BitwiseOp.And()
					Or: sil.BitwiseOp.Or()
					Xor: sil.BitwiseOp.Xor()
					Shr:
						case ty:
							Int(signed, bits):
								if signed:
									sil.BitwiseOp.Sar()
								else:
									sil.BitwiseOp.Shr()
						else:
							unimplemented("Shift right for non-integer types")
					Shl: sil.BitwiseOp.Shl()
				let dst = new_tmp(ty: lhs.value.ty)
				emit(sil.OpCode.Bitop(dst, op2, lhs: lhs.value, rhs: rhs.value))
				push(dst, ty, owned: false)
			DecRef(index):
				panic("Dec ref not implemented")
			LoadFunc(index):
				let name = get_function_name(index)
				let address = sil.Address.Global(name, mutable: true)
				let dst_value = new_tmp(ty: get_ptr_type())
				emit(sil.OpCode.GetAddress(dst_value, address))
				push(dst_value, ty: bc.Type.FuncPtr(), owned: false)

	fn get_function_name(index: int) -> str:
		if index < m_bc_program.extern_functions.len():
			let function = m_bc_program.extern_functions.get(index)
			function.name
		else:
			index = index - m_bc_program.extern_functions.len()
			let function = m_bc_program.functions.get(index)
			function.name

	fn transfer_to_owned(address: TypedAddress, value: TypedValue):
		if not value.owned:
			inc_ref(value)
		gen_load(address, owned: true)
		dec_ref(pop())

	fn gen_load(address: TypedAddress, owned: bool):
		"""Load value from address"""
		let value = new_tmp(ty: get_sil_type(ty: address.ty))
		emit(sil.OpCode.Load(dst: value, address: address.address))
		push(value, ty: address.ty, owned)

	fn gen_store(address: TypedAddress, value: TypedValue):
		emit(sil.OpCode.Store(address: address.address, value: value.value))

	fn gen_element_address(base: TypedValue, index: TypedValue) -> TypedAddress:
		"""base + index * sizeof"""
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
		let arguments2 = pop_n(count: n_args)
		let arguments: Vector[sil.Value] = new_vector_with_capacity(capacity: arguments2.len())
		for argument in arguments2:
			arguments.append(argument.value)

		if return_types.is_empty():
			emit(sil.OpCode.Call(Option.None(), callee, arguments))
		else:
			let ty = return_types.get(index: 0)
			let value = new_tmp(ty: get_sil_type(ty))
			if return_types.len() > 1:
				let new_arguments: Vector[sil.Value] = new_vector_with_capacity(capacity: arguments.len() + return_types.len() - 1)
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
				new_arguments.extend(arguments)

				emit(sil.OpCode.Call(Option.Some(value), callee, arguments: new_arguments))
				push(value, ty, owned: true)
				for address in extra_values:
					gen_load(address, owned: true)
			else:
				emit(sil.OpCode.Call(Option.Some(value), callee, arguments))
				push(value, ty, owned: true)

		for argument in arguments2:
			if is_heap(argument.ty) and argument.owned:
				dec_ref(argument)

	fn call_rt_malloc(size: sil.Value, ty: bc.Type):
		call_rt_function_1(name: "rt_malloc", ty, argument: size)

	fn call_rt_function_1(name: str, ty: bc.Type, argument: sil.Value):
		let arguments: Vector[sil.Value] = vec1(argument)
		call_rt_function(name, ty, arguments)

	fn call_rt_function_2(name: str, ty: bc.Type, argument1: sil.Value, argument2: sil.Value):
		let arguments: Vector[sil.Value] = vec2(argument1, argument2)
		call_rt_function(name, ty, arguments)

	fn call_rt_function(name: str, ty: bc.Type, arguments: Vector[sil.Value]):
		"""Invoke runtime helper function"""
		let callee = sil.Address.Global(name, mutable: false)
		let value = new_tmp(ty: get_sil_type(ty))
		emit(sil.OpCode.Call(Option.Some(value), callee, arguments))
		push(value, ty, owned: true)

	fn call_void_rt_function(name: str, arguments: Vector[sil.Value]):
		let callee = sil.Address.Global(name, mutable: false)
		emit(sil.OpCode.Call(Option.None(), callee, arguments))

	fn load_int(value: int) -> sil.Value:
		let dst = new_tmp(ty: get_word_type())
		emit(sil.OpCode.Const(dst, value))
		dst

	fn load_null_ptr() -> TypedValue:
		let dst = new_tmp(ty: get_word_type())
		emit(sil.OpCode.Const(dst, value: 0))
		TypedValue(value: dst, ty: bc.Type.Ptr(), owned: true)

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

	fn new_tmp_id() -> uint32:
		let id = m_tmp_number
		m_tmp_number += 1
		uint32(id)

	fn new_id() -> int:
		m_lit_id_number += 1
		m_lit_id_number

	fn new_global(name?: str) -> sil.Address:
		sil.Address.Global(name, mutable: false)

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
		sil.Address.Global(name, mutable: false)

	fn push_int(value?: int):
		let dst = load_int(value)
		push(dst, ty: bc.Type.Int(signed: true, bits: 64), owned: false)

	fn push(value?: sil.Value, ty: bc.Type, owned: bool):
		m_value_stack.append(TypedValue(value, ty, owned))

	fn pop() -> TypedValue:
		m_value_stack.pop_last()

	fn drop(value?: TypedValue):
		if is_heap(value.ty) and value.owned:
			dec_ref(value)

	fn inc_ref(value?: TypedValue):
		if is_heap(value.ty):
			call_void_rt_function(name: "rt_inc_ref", arguments: vec1(value.value))

	fn dec_ref(value?: TypedValue):
		if is_heap(value.ty):
			call_void_rt_function(name: "rt_dec_ref", arguments: vec1(value.value))

	fn pop_n(count: int) -> List[TypedValue]:
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
					panic("Block already terminated!")
				else:
					if sil.is_terminating_op(op):
						m_block_is_terminated = true
				block.instructions.append(instruction)
			None:
				panic("Cannot emit")

fn pack_f64(value: float64) -> Bytes:
	"""Place 64 bits float into 8 bytes"""
	let ba = ByteArray()
	ba.pack_f64_le(value)
	ba.to_bytes()

fn pack_f32(value: float32) -> Bytes:
	"""Place 32 bits float into 4 bytes"""
	let ba = ByteArray()
	ba.pack_f32_le(value)
	ba.to_bytes()

fn pack_i64(value: int) -> Bytes:
	"""Place 64 bits integer into 8 bytes"""
	let ba = ByteArray()
	ba.pack_u64_le(value)
	ba.to_bytes()

fn pack_i32(value: int32) -> Bytes:
	"""Place 64 bits integer into 8 bytes"""
	let ba = ByteArray()
	ba.pack_u32_le(int(value))
	ba.to_bytes()

fn pack_i16(value: int16) -> Bytes:
	"""Place 64 bits integer into 8 bytes"""
	let ba = ByteArray()
	ba.pack_u64_le(int(value))
	ba.to_bytes()

fn pack_i8(value: int8) -> Bytes:
	"""Place 64 bits integer into 8 bytes"""
	let ba = ByteArray()
	ba.pack_u64_le(int(value))
	ba.to_bytes()

fn pack_u64(value: uint64) -> Bytes:
	"""Place 64 bits integer into 8 bytes"""
	let ba = ByteArray()
	ba.pack_u64_le(int(value))  # TODO: do not cast?
	ba.to_bytes()

fn pack_u32(value: uint32) -> Bytes:
	"""Place 64 bits integer into 8 bytes"""
	let ba = ByteArray()
	ba.pack_u64_le(int(value))  # TODO: do not cast?
	ba.to_bytes()

fn pack_u16(value: uint16) -> Bytes:
	"""Place 64 bits integer into 8 bytes"""
	let ba = ByteArray()
	ba.pack_u64_le(int(value))  # TODO: do not cast?
	ba.to_bytes()

fn pack_u8(value: uint8) -> Bytes:
	"""Place 64 bits integer into 8 bytes"""
	let ba = ByteArray()
	ba.pack_u64_le(int(value))  # TODO: do not cast?
	ba.to_bytes()

fn pack_str(text: str) -> Bytes:
	bytes_from_ascii(text).concat(other: fill_bytes(n: 1, fill: 0))
