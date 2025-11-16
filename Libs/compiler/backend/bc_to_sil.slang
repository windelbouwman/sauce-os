""" Transform BC into SIL

Features of this pass:

- Compile structured types into pointers with load/store operations
- Implement multiply and divide by either physical instructions or a function call to a library

"""

from std import ord
from listtype import List
from vectype import Vector, new_vector
from optiontype import Option
from bytes import Bytes, bytes_from_ascii, fill_bytes
from utils import panic, unimplemented
from logging import log_info
import bc
import sil

pub struct SilGenOptions:
	""" Target specific options """
	has_div: bool
	has_mul: bool
	has_fpu: bool
	word_size: int

pub fn to_sil(program: bc.Program) -> sil.Program:
	# TODO: pass options, su
	log_info("Creating SIL program from bytecode")
	let g = SilGen(m_bc_program: program)
	g.gen_program()

struct StructLayout:
	""" Information how a structure is mapped into memory """
	size: int  # Size of entire struct
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

class SilGen:
	var m_bc_program: bc.Program
	var m_externs: List[sil.Extern] = List()
	var m_structs: Vector[StructLayout] = new_vector()
	var m_functions: List[sil.Function] = List()
	var m_blobs: List[sil.DataBlob] = List()
	var m_blocks: List[sil.Block] = List()
	var m_current_block: Option[sil.Block] = Option.None()
	var m_block_is_terminated: bool = false
	var m_parameters: List[TypedAddress] = List()
	var m_locals: List[TypedAddress] = List()
	var m_tmp_number: int = 0
	var m_value_stack: List[TypedValue] = List()
	var m_stack_offset: int = 0

	pub fn gen_program() -> sil.Program:
		# Define used runtime functions:
		m_externs.append(sil.Extern(name: "rt_malloc"))
		m_externs.append(sil.Extern(name: "slangrt_box_int64"))

		for extern_function in m_bc_program.extern_functions:
			m_externs.append(sil.Extern(name: extern_function.name))

		for struct_def in m_bc_program.structs:
			calc_struct_layout(struct_def)

		for function in m_bc_program.functions:
			gen_function(function)
		sil.Program(externs: m_externs, functions: m_functions, blobs: m_blobs)

	fn calc_struct_layout(struct_def: bc.Struct):
		var offset = 0
		let fields: Vector[StructField] = new_vector()
		for field in struct_def.fields:
			fields.append(StructField(offset, ty: field.ty))
			# TODO: take alignment into account
			offset += get_size_of(field.ty)
		m_structs.append(StructLayout(size: offset, fields))

	fn get_size_of(ty?: bc.Type) -> int:
		case ty:
			Int(signed, bits):
				8 # TODO
			Bool:
				8
			Char:
				8
			Str:
				8
			Ptr:
				8
			Float(bits):
				8 # TODO
			Array(element_type):
				8
			StructRef(index):
				8
			Function(parameter_types, return_type):
				8

	fn gen_function(function: bc.Function):
		log_info("Gen code for function {function.name}")
		m_blocks = List()
		m_value_stack = List()
		m_parameters = List()
		m_locals.clear()
		m_stack_offset = 0
		let start = new_block(name: "start")
		set_current_block(start)

		let parameters: List[sil.Value] = List()
		for parameter in function.parameters:
			let p = new_tmp()
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
		var index = 0
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
			Literal(literal):
				case literal:
					Int(value):
						push_int(value)
					Float(value):
						unimplemented("float literal")
						# push_int(99999) # TODO
					Str(value):
						let data = bytes_from_ascii(text: value).concat(other: fill_bytes(n: 1, fill: 0))
						let literal_address = add_data_blob(data)
						let dst_value = new_tmp()
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
				let byte_size_tmp = new_tmp()
				emit(sil.OpCode.Const(byte_size_tmp, size))
				call_rt_malloc(size: byte_size_tmp, ty: bc.Type.StructRef(index))
			ArrayLiteral(ty):
				let count_tmp = pop()
				let element_size = get_size_of(ty)
				let element_size_tmp = new_tmp()
				emit(sil.OpCode.Const(element_size_tmp, element_size))
				let byte_size_tmp = new_tmp()
				emit(sil.OpCode.Binop(dst: byte_size_tmp, op2: sil.BinaryOp.Mul(), lhs: count_tmp.value, rhs: element_size_tmp))
				call_rt_malloc(size: byte_size_tmp, ty: bc.Type.Array(ty))
			ToOpaque(ty3):
				case ty3:
					Int(signed, bits):
						let value = pop()
						let name = "slangrt_box_int{bits}" if signed else "slangrt_box_uint{bits}"
						call_rt_function_1(name, ty: bc.Type.Ptr(), argument: value.value)
					Ptr:
						pass
					StructRef(index):
						let value = pop()
						push(value.value, ty: bc.Type.Ptr())
				else:
					unimplemented("To opaque")
			FromOpaque(ty):
				case ty:
					Int(signed, bits):
						let value = pop()
						let name = "slangrt_unbox_int{bits}" if signed else "slangrt_unbox_uint{bits}"
						call_rt_function_1(name, ty, argument: value.value)
					Ptr:
						pass
					StructRef(index):
						let value = pop()
						push(value.value, ty)
				else:
					unimplemented("from opaque")
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
					Multiply:
						sil.BinaryOp.Mul()
				let dst = new_tmp()
				push(dst, ty: lhs.ty)
				emit(sil.OpCode.Binop(dst, op2, lhs: lhs.value, rhs: rhs.value))
			GlobalGet(index):
				# gen_load(addr)
				unimplemented("Global get")
			GlobalSet(index):
				unimplemented("Global set")
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
					gen_call(callee, n_args: function.parameters.len(), return_type: function.return_type)
				else:
					index = index - m_bc_program.extern_functions.len()
					let function = m_bc_program.functions[index]
					let callee = new_global(function.name)
					gen_call(callee, n_args: function.parameters.len(), return_type: function.return_type)
			Return(v):
				if v == 0:
					emit(sil.OpCode.Return(value: Option.None()))
				elif v == 1:
					let value = pop()
					emit(sil.OpCode.Return(value: Option.Some(value.value)))
			Unreachable:
				emit(sil.OpCode.Halt())
		else:
			unimplemented(bc.instruction_to_string(opcode))

	fn gen_load(address: TypedAddress):
		""" Load value from address """
		let value = new_tmp()
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
		let offset = new_tmp()
		let addr = new_tmp()
		let size_of = new_tmp()
		emit(sil.OpCode.Const(size_of, element_size))
		emit(sil.OpCode.Binop(dst: offset, op: sil.BinaryOp.Mul(), lhs: index.value, rhs: size_of))
		emit(sil.OpCode.Binop(dst: addr, op: sil.BinaryOp.Add(), lhs: base.value, rhs: offset))
		TypedAddress(address: sil.Address.Ptr(addr, offset: 0), ty: element_ty)

	fn gen_struct_address(base: TypedValue, index: int) -> TypedAddress:
		let struct_index = case base.ty:
			StructRef(index):
				index
		else:
			panic("Cannot get struct field address of non struct type")
		let struct_layout = m_structs.get(index: struct_index)
		let field = struct_layout.fields.get(index)
		let offset = new_tmp()
		emit(sil.OpCode.Const(offset, field.offset))
		let addr = new_tmp()
		emit(sil.OpCode.Binop(dst: addr, op: sil.BinaryOp.Add(), lhs: base.value, rhs: offset))
		TypedAddress(address: sil.Address.Ptr(addr, offset: 0), ty: field.ty)

	fn gen_call(callee: sil.Address, n_args: int, return_type: Option[bc.Type]):
		let arguments = pop_n(count: n_args)
		case return_type:
			Some(ty):
				let value = new_tmp()
				emit(sil.OpCode.Call(Option.Some(value), callee, arguments))
				push(value, ty)
			None:
				emit(sil.OpCode.Call(Option.None(), callee, arguments))

	fn call_rt_malloc(size: sil.Value, ty: bc.Type):
		call_rt_function_1(name: "rt_malloc", ty, argument: size)

	fn call_rt_function_1(name: str, ty: bc.Type, argument: sil.Value):
		let arguments: List[sil.Value] = List()
		arguments.append(argument)
		call_rt_function(name, ty, arguments)

	fn call_rt_function(name: str, ty: bc.Type, arguments: List[sil.Value]):
		""" Invoke runtime helper function """
		let callee = sil.Address.Global(name)
		let value = new_tmp()
		emit(sil.OpCode.Call(Option.Some(value), callee, arguments))
		push(value, ty)

	fn new_block(name: str) -> sil.Block:
		let block = sil.Block(name, instructions: List())
		m_blocks.append(block)
		block

	fn new_tmp() -> sil.Value:
		sil.Value.Tmp(name: "x{new_id()}")

	fn new_stack_slot(size: int) -> sil.Address:
		let offset = m_stack_offset
		m_stack_offset += size
		sil.Address.StackSlot(offset)

	fn new_id() -> int:
		m_tmp_number += 1
		m_tmp_number

	fn new_global(name?: str) -> sil.Address:
		sil.Address.Global(name)

	fn add_data_blob(data?: Bytes) -> sil.Address:
		# TODO: we have a chance to deduplicate blobs here!
		let name = "lit_{new_id()}"
		m_blobs.append(sil.DataBlob(name, data))
		sil.Address.Global(name)

	fn push_int(value?: int):
		let dst = new_tmp()
		emit(sil.OpCode.Const(dst, value))
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

	fn set_current_block(block?: sil.Block):
		m_current_block = Option.Some(block)
		m_block_is_terminated = false

	fn emit(op?: sil.OpCode):
		case m_current_block:
			Some(block):
				if m_block_is_terminated:
					panic("Block already terminated!")
				else:
					case op:
						Jump(label):
							m_block_is_terminated = true
						JumpIf(lhs, c, rhs, label1, label2):
							m_block_is_terminated = true
						Return(value):
							m_block_is_terminated = true
						Halt:
							m_block_is_terminated = true
					else:
						pass
				let instruction = sil.Instruction(op)
				block.instructions.append(instruction)
			None:
				panic("Cannot emit")
