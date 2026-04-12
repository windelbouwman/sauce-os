module compiler.vm
"""Virtual machine for bytecode."""

from base.listtype import List
from base.optiontype import Option
from base.hashmap import HashMap, new_hashmap_str
from base.vectype import Vector, new_vector
from base.utils import panic, assert, unimplemented
from base.logging import log_debug
from bc import Instruction, Program, Function, instruction_to_string
from std import print, float_to_str
import std
import bc
import rt

pub enum Value:
	Int64(value: int64)
	Int32(value: int32)
	Int16(value: int16)
	Int8(value: int8)
	Uint64(value: uint64)
	Uint32(value: uint32)
	Uint16(value: uint16)
	Uint8(value: uint8)
	Str(value: str)
	Char(value: char)
	Float(value: float)
	Bool(value: bool)
	List(list: ListValue)
	Null
	Undefined

enum FunctionRef:
	ByteCode(func: bc.Function)
	Native(func: ExternFunctionImpl)

struct ListValue:
	values: List[Value]

pub fn value_to_string(value?: Value) -> str:
	case value:
		Int64(value):
			"int64({value})"
		Int32(value):
			"int32({int(value)})"
		Int16(value):
			"int16({int(value)})"
		Int8(value):
			"int8({int(value)})"
		Uint64(value):
			"uint64({int(value)})"
		Uint32(value):
			"uint32({int(value)})"
		Uint16(value):
			"uint16({int(value)})"
		Uint8(value):
			"uint8({int(value)})"
		Str(value):
			"str({value})"
		Char(value):
			"char({value})"
		Float(value):
			"float({float_to_str(value)})"
		Bool(value):
			if value:
				"bool(true)"
			else:
				"bool(false)"
		List(values):
			"List(..)"
		Null:
			"Null"
		Undefined:
			"undefined"

fn bool_from_value(value?: Value) -> bool:
	case value:
		Bool(value):
			value
	else:
		panic("bool_from_value: no boolean")

fn str_from_value(value?: Value) -> str:
	case value:
		Str(value):
			value
	else:
		panic("str_from_value: no str ({value_to_string(value)})")

fn int64_from_value(value?: Value) -> int64:
	case value:
		Int64(value):
			value
	else:
		panic("int64_from_value: no int64")

fn int32_from_value(value?: Value) -> int32:
	case value:
		Int32(value):
			value
	else:
		panic("int32_from_value: no int32")

fn uint64_from_value(value?: Value) -> uint64:
	case value:
		Uint64(value):
			value
	else:
		panic("uint64_from_value: no uint64")

fn uint32_from_value(value?: Value) -> uint32:
	case value:
		Uint32(value):
			value
	else:
		panic("uint32_from_value: no uint32")

fn char_from_value(value?: Value) -> char:
	case value:
		Char(value):
			value
	else:
		panic("char_from_value: no char")

fn float_from_value(value?: Value) -> float:
	case value:
		Float(value):
			value
	else:
		panic("float_from_value: no float")

fn list_from_value(value?: Value) -> ListValue:
	case value:
		List(list):
			list
	else:
		panic("list_from_value: no list")

struct ExternFunctionImpl:
	f: fn(List[Value]) -> Option[Value]
	n: int

fn efi_std_ord(arguments: List[Value]) -> Option[Value]:
	let value = std.ord(char_from_value(arguments[0]))
	Option.Some(Value.Int64(value))

fn efi_std_chr(arguments: List[Value]) -> Option[Value]:
	let value = std.chr(int64_from_value(arguments[0]))
	Option.Some(Value.Char(value))

fn efi_std_float_to_str(arguments: List[Value]) -> Option[Value]:
	let value = std.float_to_str(float_from_value(arguments[0]))
	Option.Some(Value.Str(value))

fn efi_std_float_to_str2(arguments: List[Value]) -> Option[Value]:
	let value = std.float_to_str2(value: float_from_value(arguments[0]), digits: int64_from_value(arguments[1]))
	Option.Some(Value.Str(value))

fn efi_std_str_len(arguments: List[Value]) -> Option[Value]:
	let text = str_from_value(arguments[0])
	let value = std.str_len(text)
	Option.Some(Value.Int64(value))

fn efi_std_str_get(arguments: List[Value]) -> Option[Value]:
	let text = str_from_value(arguments[0])
	let index = int64_from_value(arguments[1])
	let value = std.str_get(text, index)
	Option.Some(Value.Char(value))

fn efi_std_str_slice(arguments: List[Value]) -> Option[Value]:
	let text = str_from_value(arguments[0])
	let begin = int64_from_value(arguments[1])
	let end = int64_from_value(arguments[2])
	let value = std.str_slice(text, begin, end)
	Option.Some(Value.Str(value))

fn efi_std_print(arguments: List[Value]) -> Option[Value]:
	std.print(str_from_value(arguments.first()))
	Option.None()

fn efi_std_read_line(arguments: List[Value]) -> Option[Value]:
	let value = std.read_line(prompt: str_from_value(arguments.first()))
	Option.Some(Value.Str(value))

fn efi_default(arguments: List[Value]) -> Option[Value]:
	panic("Not impl EFI")
	Option.None()

fn efi_rt_int_to_str(arguments: List[Value]) -> Option[Value]:
	let value = rt.int_to_str(int64_from_value(arguments[0]))
	Option.Some(Value.Str(value))

fn efi_rt_char_to_str(arguments: List[Value]) -> Option[Value]:
	let value = rt.char_to_str(char_from_value(arguments[0]))
	Option.Some(Value.Str(value))

fn efi_rt_str_concat(arguments: List[Value]) -> Option[Value]:
	let a = str_from_value(arguments[0])
	let b = str_from_value(arguments[1])
	# let value = rt.str_concat(a, b)
	let value = a + b
	Option.Some(Value.Str(value))

fn efi_rt_str_compare(arguments: List[Value]) -> Option[Value]:
	let a = str_from_value(arguments[0])
	let b = str_from_value(arguments[1])
	# let value = rt.str_compare(a, b)
	let value = a == b
	Option.Some(Value.Bool(value))

fn get_efi_db() -> HashMap[str,ExternFunctionImpl]:
	# Link in external functions:
	let efi_db: HashMap[str,ExternFunctionImpl] = new_hashmap_str()

	# std:
	efi_db.insert(key: "std_ord", value: ExternFunctionImpl(f: efi_std_ord, n: 1))
	efi_db.insert(key: "std_chr", value: ExternFunctionImpl(f: efi_std_chr, n: 1))
	efi_db.insert(key: "std_float_to_str", value: ExternFunctionImpl(f: efi_std_float_to_str, n: 1))
	efi_db.insert(key: "std_float_to_str2", value: ExternFunctionImpl(f: efi_std_float_to_str2, n: 2))
	efi_db.insert(key: "std_str_len", value: ExternFunctionImpl(f: efi_std_str_len, n: 1))
	efi_db.insert(key: "std_str_get", value: ExternFunctionImpl(f: efi_std_str_get, n: 2))
	efi_db.insert(key: "std_str_slice", value: ExternFunctionImpl(f: efi_std_str_slice, n: 3))
	efi_db.insert(key: "std_print", value: ExternFunctionImpl(f: efi_std_print, n: 1))
	efi_db.insert(key: "std_read_line", value: ExternFunctionImpl(f: efi_std_read_line, n: 1))
	efi_db.insert(key: "std_get_path_separator", value: ExternFunctionImpl(f: efi_default, n: 0))
	efi_db.insert(key: "std_exit", value: ExternFunctionImpl(f: efi_default, n: 1))
	efi_db.insert(key: "std_read_file", value: ExternFunctionImpl(f: efi_default, n: 1))
	efi_db.insert(key: "std_file_get_stdin", value: ExternFunctionImpl(f: efi_default, n: 0))
	efi_db.insert(key: "std_file_get_stdout", value: ExternFunctionImpl(f: efi_default, n: 0))
	efi_db.insert(key: "std_file_open", value: ExternFunctionImpl(f: efi_default, n: 2))
	efi_db.insert(key: "std_file_readln", value: ExternFunctionImpl(f: efi_default, n: 1))
	efi_db.insert(key: "std_file_write", value: ExternFunctionImpl(f: efi_default, n: 2))
	efi_db.insert(key: "std_file_writeln", value: ExternFunctionImpl(f: efi_default, n: 2))
	efi_db.insert(key: "std_file_read_n_bytes", value: ExternFunctionImpl(f: efi_default, n: 3))
	efi_db.insert(key: "std_file_write_n_bytes", value: ExternFunctionImpl(f: efi_default, n: 3))
	efi_db.insert(key: "std_file_close", value: ExternFunctionImpl(f: efi_default, n: 1))
	efi_db.insert(key: "std_get_n_args", value: ExternFunctionImpl(f: efi_default, n: 0))
	efi_db.insert(key: "std_get_arg", value: ExternFunctionImpl(f: efi_default, n: 1))

	# rt:
	efi_db.insert(key: "rt_int_to_str", value: ExternFunctionImpl(f: efi_rt_int_to_str, n: 1))
	efi_db.insert(key: "rt_char_to_str", value: ExternFunctionImpl(f: efi_rt_char_to_str, n: 1))
	efi_db.insert(key: "rt_str_concat", value: ExternFunctionImpl(f: efi_rt_str_concat, n: 2))
	efi_db.insert(key: "rt_str_compare", value: ExternFunctionImpl(f: efi_rt_str_compare, n: 2))
	efi_db.insert(key: "rt_str_len", value: ExternFunctionImpl(f: efi_std_str_len, n: 1))
	efi_db.insert(key: "rt_str_get", value: ExternFunctionImpl(f: efi_std_str_get, n: 2))
	efi_db

pub fn prepare_vm(vm: VirtualMachine, program: Program):
	vm.structs = program.structs

	# Link external functions:
	let efi_db = get_efi_db()
	for e in program.extern_functions:
		if efi_db.contains(key: e.name):
			let efi = efi_db.get(key: e.name)
			assert(condition: e.parameters.len() == efi.n, message: "n should match len(parameters)")
			vm.m_functions.append(FunctionRef.Native(efi))
		else:
			let efi = ExternFunctionImpl(f: efi_default, n: 0)
			vm.m_functions.append(FunctionRef.Native(efi))
			# panic("Missing extern function: {e.name}")
	for f in program.functions:
		vm.m_functions.append(FunctionRef.ByteCode(f))

pub fn run_bytecode(program: Program, entry_function: str):
	let vm = VirtualMachine()
	prepare_vm(vm, program)

	# Initialize global variables:
	for g in program.globals:
		case g.value:
			Some(value):
				vm.globals.append(eval_code(vm, code: value))
			None:
				unimplemented("External variables")

	let top_frame = Frame(code: new_vector())
	vm.push_frame(frame: top_frame)

	# Create mapping from names to index:
	let function_name_to_index: HashMap[str,int] = new_hashmap_str()
	var index = 0
	for function in program.functions:
		function_name_to_index.insert(key: function.name, value: index)
		index += 1
	let entry_function_index = function_name_to_index.get(key: entry_function)

	let function = program.functions[entry_function_index]
	let arguments: List[Value] = List()
	let frame = frame_from_function(function, arguments)
	vm.push_frame(frame)
	while vm.frames.len() > 1:
		vm.step()

pub fn eval_code(vm: VirtualMachine, code: Vector[Instruction]) -> Value:
	"""Evaluate a bytecode expression"""
	let top_frame = Frame(code: new_vector())
	vm.push_frame(frame: top_frame)

	let frame = Frame(code)
	vm.push_frame(frame)
	while vm.frames.len() > 1:
		vm.step()

	vm.pop_frame().stack.last()


fn frame_from_function(function: Function, arguments: List[Value]) -> Frame:
	let frame = Frame(code: function.instructions)
	for x in function.parameters:
		pass

	for x in arguments:
		frame.arguments.append(x)

	# Fill space for local variables:
	for x in function.locals:
		frame.locals.append(Value.Undefined())
	frame

class Frame:
	pub var arguments: List[Value] = List()
	pub var locals: List[Value] = List()
	pub var stack: List[Value] = List()
	pub var pc: int = 0
	var code: Vector[Instruction]

	pub fn fetch() -> Instruction:
		let instruction = code[pc]
		pc += 1
		instruction

pub class VirtualMachine:
	pub var frames: List[Frame] = List()
	pub var globals: Vector[Value] = new_vector()
	pub var m_functions: List[FunctionRef] = List()
	pub var structs: Vector[bc.Struct] = new_vector()

	pub fn step():
		let instruction = fetch()
		execute(instruction)

	fn fetch() -> Instruction:
		frames.last().fetch()

	fn execute(instruction: Instruction):
		log_debug("Executing: {instruction_to_string(instruction)}")
		case instruction:
			Nop:
				pass
			Dup:
				let value = pop()
				push(value)
				push(value)
			Swap:
				let value1 = pop()
				let value2 = pop()
				push(value1)
				push(value2)
			Literal(literal):
				case literal:
					Int(val):
						push(Value.Int64(val))
					Str(val):
						push(Value.Str(val))
					Char(value):
						push(Value.Char(value))
					Bool(val):
						push(Value.Bool(val))
					Float(val):
						push(Value.Float(val))
					Null:
						push(Value.Null())
			LocalGet(index):
				let value = get_local(index)
				push(value)
			LocalSet(index):
				set_local(index, value: pop())
			GlobalGet(index):
				let value = get_global(index)
				push(value)
			GlobalSet(index):
				set_global(index, value: pop())
			ParameterGet(index):
				let value = get_parameter(index)
				push(value)
			ParameterSet(index):
				set_parameter(index, value: pop())
			GetAttr(index):
				let base = pop()
				let list = list_from_value(base)
				let value = list.values.get(index)
				push(value)
			SetAttr(index):
				let value = pop()
				let base = pop()
				let list = list_from_value(base)
				list.values.set(index, value)
			GetIndex:
				let index = pop()
				let base = pop()
				let list = list_from_value(base)
				let index2 = int64_from_value(index)
				let value = list.values.get(index: index2)
				push(value)
			SetIndex:
				let value = pop()
				let index = pop()
				let base = pop()
				let list = list_from_value(base)
				let index2 = int64_from_value(index)
				list.values.set(index: index2, value)
			Not:
				let value = pop()
				if bool_from_value(value):
					push(Value.Bool(false))
				else:
					push(Value.Bool(true))
			Neg:
				let value = pop()
				case value:
					Int64(v):
						push(Value.Int64(-v))
					Float(v):
						push(Value.Float(-v))
				else:
					panic("Cannot negate: {value_to_string(value)}")
			Binop(op, ty):
				let rhs = pop()
				let lhs = pop()
				case ty:
					Int(signed, bits):
						if signed:
							if bits == 64:
								let lhs_value = int64_from_value(lhs)
								let rhs_value = int64_from_value(rhs)
								let value = eval_binop_int64(op, lhs: lhs_value, rhs: rhs_value)
								push(Value.Int64(value))
							else:
								let lhs_value = int32_from_value(lhs)
								let rhs_value = int32_from_value(rhs)
								let value = eval_binop_int32(op, lhs: lhs_value, rhs: rhs_value)
								push(Value.Int32(value))
						else:
							if bits == 64:
								let lhs_value = uint64_from_value(lhs)
								let rhs_value = uint64_from_value(rhs)
								let value = eval_binop_uint64(op, lhs: lhs_value, rhs: rhs_value)
								push(Value.Uint64(value))
							else:
								let lhs_value = uint32_from_value(lhs)
								let rhs_value = uint32_from_value(rhs)
								let value = eval_binop_uint32(op, lhs: lhs_value, rhs: rhs_value)
								push(Value.Uint32(value))
					Float(bits):
						let lhs_value = float_from_value(lhs)
						let rhs_value = float_from_value(rhs)
						let value = eval_binop_float(op, lhs: lhs_value, rhs: rhs_value)
						push(Value.Float(value))
				else:
					panic("Cannot binop")
			Bitop(op, ty):
				let rhs = pop()
				let lhs = pop()
				case ty:
					Int(signed, bits):
						if signed:
							if bits == 64:
								let lhs_value = int64_from_value(lhs)
								let rhs_value = int64_from_value(rhs)
								let value = eval_bitop_int64(op, lhs: lhs_value, rhs: rhs_value)
								push(Value.Int64(value))
							else:
								let lhs_value = int32_from_value(lhs)
								let rhs_value = int32_from_value(rhs)
								let value = eval_bitop_int32(op, lhs: lhs_value, rhs: rhs_value)
								push(Value.Int32(value))
						else:
							if bits == 64:
								let lhs_value = uint64_from_value(lhs)
								let rhs_value = uint64_from_value(rhs)
								let value = eval_bitop_uint64(op, lhs: lhs_value, rhs: rhs_value)
								push(Value.Uint64(value))
							else:
								let lhs_value = uint32_from_value(lhs)
								let rhs_value = uint32_from_value(rhs)
								let value = eval_bitop_uint32(op, lhs: lhs_value, rhs: rhs_value)
								push(Value.Uint32(value))
				else:
					panic("Can only bit fiddle with integer types")
			IntToFloat(bits):
				let vm_value = pop()
				case vm_value:
					Int64(value):
						push(Value.Float(float(value)))
					Int32(value):
						push(Value.Float(float(value)))
					# Int16(value):
					# 	push(Value.Float(float(value)))
					# Int8(value):
					# 	push(Value.Float(float(value)))
					Uint64(value):
						push(Value.Float(float(value)))
					Uint32(value):
						push(Value.Float(float(value)))
					# Uint16(value):
					# 	push(Value.Float(float(value)))
					# Uint8(value):
					# 	push(Value.Float(float(value)))
				else:
					panic("Can only cast integers to float")
			FloatToInt(signed, bits):
				let value = float_from_value(value: pop())
				if signed:
					if bits == 64:
						let new_value = int64(value)
						push(Value.Int64(new_value))
					else:
						let new_value = int32(value)
						push(Value.Int32(new_value))
				else:
					if bits == 64:
						let new_value = uint64(value)
						push(Value.Uint64(new_value))
					else:
						let new_value = uint32(value)
						push(Value.Uint32(new_value))
			IntCast(signed, bits):
				let vm_value = pop()
				case vm_value:
					Int64(value):
						if signed:
							switch bits:
								64: push(Value.Int64(int64(value)))
								32: push(Value.Int32(int32(value)))
								16: push(Value.Int32(int32(value)))
								8: push(Value.Int32(int32(value)))
								# 16: push(Value.Int16(int16(value)))
								# 8: push(Value.Int8(int8(value)))
							else:
								panic("Cannot bit cast to {bits} bits")
						else:
							switch bits:
								64: push(Value.Uint64(uint64(value)))
								32: push(Value.Uint32(uint32(value)))
								16: push(Value.Uint32(uint32(value)))
								8: push(Value.Uint32(uint32(value)))
								# 16: push(Value.Uint16(uint16(value)))
								# 8: push(Value.Uint8(uint8(value)))
							else:
								panic("Cannot bit cast to {bits} bits")
					Int32(value):
						if signed:
							if bits == 64:
								push(Value.Int64(int64(value)))
							else:
								push(Value.Int32(int32(value)))
						else:
							if bits == 64:
								push(Value.Uint64(uint64(value)))
							else:
								push(Value.Uint32(uint32(value)))
					Int16(value):
						if signed:
							if bits == 64:
								push(Value.Int64(int64(value)))
							else:
								push(Value.Int32(int32(value)))
						else:
							if bits == 64:
								push(Value.Uint64(uint64(value)))
							else:
								push(Value.Uint32(uint32(value)))
					Int8(value):
						if signed:
							if bits == 64:
								push(Value.Int64(int64(value)))
							else:
								push(Value.Int32(int32(value)))
						else:
							if bits == 64:
								push(Value.Uint64(uint64(value)))
							else:
								push(Value.Uint32(uint32(value)))
					Uint64(value):
						if signed:
							if bits == 64:
								push(Value.Int64(int64(value)))
							else:
								push(Value.Int32(int32(value)))
						else:
							if bits == 64:
								push(Value.Uint64(uint64(value)))
							else:
								push(Value.Uint32(uint32(value)))
					Uint32(value):
						if signed:
							if bits == 64:
								push(Value.Int64(int64(value)))
							else:
								push(Value.Int32(int32(value)))
						else:
							if bits == 64:
								push(Value.Uint64(uint64(value)))
							else:
								push(Value.Uint32(uint32(value)))
					Uint16(value):
						if signed:
							if bits == 64:
								push(Value.Int64(int64(value)))
							else:
								push(Value.Int32(int32(value)))
						else:
							if bits == 64:
								push(Value.Uint64(uint64(value)))
							else:
								push(Value.Uint32(uint32(value)))
					Uint8(value):
						if signed:
							if bits == 64:
								push(Value.Int64(int64(value)))
							else:
								push(Value.Int32(int32(value)))
						else:
							if bits == 64:
								push(Value.Uint64(uint64(value)))
							else:
								push(Value.Uint32(uint32(value)))
				else:
					panic("Can only int cast int types")
			FloatCast(bits):
				pass  # No-op?
			FromOpaque(ty):
				pass  # VM values are all opaque
			ToOpaque(ty):
				pass  # VM values are all opaque
			Jump(target):
				jump(target)
			JumpIf(op, target1, target2):
				let rhs = pop()
				let lhs = pop()
				if eval_comparison(op, lhs, rhs):
					jump(target1)
				else:
					jump(target2)
			Call(index):
				log_debug("Call function!")
				let function_ref = m_functions.get(index)
				case function_ref:
					ByteCode(function):
						let n = function.parameters.len()
						let arguments = pop_n(count: n)
						let frame = frame_from_function(function, arguments)
						push_frame(frame)
					Native(efi):
						let arguments = pop_n(count: efi.n)
						case efi.f(arguments):
							Some(value):
								push(value)
							None:
								pass
			CallIndirect(parameter_types, return_type):
				let func_pointer = pop()
				let index = int64_from_value(func_pointer)
				let n = parameter_types.len()
				let arguments = pop_n(count: n)
				let function_ref = m_functions.get(index)
				case function_ref:
					ByteCode(function):
						let frame = frame_from_function(function, arguments)
						push_frame(frame)
					Native(efi):
						case efi.f(arguments):
							Some(value):
								push(value)
							None:
								pass
			Return(amount):
				if amount > 0:
					let values = pop_n(count: amount)
					let stub_frame = pop_frame()
					for value in values:
						push(value)
				else:
					let stub_frame = pop_frame()
			Unreachable:
				panic("Reached unreachable")
			DecRef(index):
				print("TODO?: dec ref {index}")
			LoadFunc(index):
				push(Value.Int64(index))
			StructLiteral(struct_index):
				let struc = structs[struct_index]
				push_empty_list(count: struc.fields.len())
			ArrayLiteral(ty):
				let size = pop()
				push_empty_list(count: int64_from_value(size))

	fn push_empty_list(count: int):
		let value = Value.Undefined()
		let values: List[Value] = List()
		while values.len() < count:
			values.append(value)
		let list = ListValue(values)
		push(Value.List(list))

	fn push(value?: Value):
		frames.last().stack.append(value)

	fn pop() -> Value:
		frames.last().stack.pop_last()

	fn pop_n(count: int) -> List[Value]:
		let values: List[Value] = List()
		while values.len() < count:
			values.prepend(pop())
		values

	fn jump(pc?: int):
		let frame = frames.last()
		frame.pc = pc

	fn get_local(index: int) -> Value:
		frames.last().locals.get(index)

	fn set_local(index: int, value: Value):
		frames.last().locals.set(index, value)

	fn get_parameter(index: int) -> Value:
		frames.last().arguments.get(index)

	fn set_parameter(index: int, value: Value):
		frames.last().arguments.set(index, value)

	fn get_global(index: int) -> Value:
		globals.get(index)

	fn set_global(index: int, value: Value):
		globals.set(index, value)

	pub fn pop_frame() -> Frame:
		frames.pop_last()

	pub fn push_frame(frame: Frame):
		frames.append(frame)

fn eval_binop_int64(op: bc.BinaryOperator, lhs: int64, rhs: int64) -> int64:
	case op:
		Add: lhs + rhs
		Sub: lhs - rhs
		Divide: lhs / rhs
		Modulo: lhs % rhs
		Multiply: lhs * rhs

fn eval_binop_int32(op: bc.BinaryOperator, lhs: int32, rhs: int32) -> int32:
	case op:
		Add: lhs + rhs
		Sub: lhs - rhs
		Divide: lhs / rhs
		Modulo: lhs % rhs
		Multiply: lhs * rhs

fn eval_binop_uint64(op: bc.BinaryOperator, lhs: uint64, rhs: uint64) -> uint64:
	case op:
		Add: lhs + rhs
		Sub: lhs - rhs
		Divide: lhs / rhs
		Modulo: lhs % rhs
		Multiply: lhs * rhs

fn eval_binop_uint32(op: bc.BinaryOperator, lhs: uint32, rhs: uint32) -> uint32:
	case op:
		Add: lhs + rhs
		Sub: lhs - rhs
		Divide: lhs / rhs
		Modulo: lhs % rhs
		Multiply: lhs * rhs

fn eval_comparison_int64(op: bc.ComparisonOperator, lhs: int64, rhs: int64) -> bool:
	case op:
		Less: lhs < rhs
		LessEquals: lhs <= rhs
		Greater: lhs > rhs
		GreaterEquals: lhs >= rhs
		Equals: lhs == rhs
		NotEquals: lhs != rhs

fn eval_comparison_int32(op: bc.ComparisonOperator, lhs: int32, rhs: int32) -> bool:
	case op:
		Less: lhs < rhs
		LessEquals: lhs <= rhs
		Greater: lhs > rhs
		GreaterEquals: lhs >= rhs
		Equals: lhs == rhs
		NotEquals: lhs != rhs

fn eval_comparison_uint64(op: bc.ComparisonOperator, lhs: uint64, rhs: uint64) -> bool:
	case op:
		Less: lhs < rhs
		LessEquals: lhs <= rhs
		Greater: lhs > rhs
		GreaterEquals: lhs >= rhs
		Equals: lhs == rhs
		NotEquals: lhs != rhs

fn eval_comparison_uint32(op: bc.ComparisonOperator, lhs: uint32, rhs: uint32) -> bool:
	case op:
		Less: lhs < rhs
		LessEquals: lhs <= rhs
		Greater: lhs > rhs
		GreaterEquals: lhs >= rhs
		Equals: lhs == rhs
		NotEquals: lhs != rhs

fn eval_binop_float(op: bc.BinaryOperator, lhs: float, rhs: float) -> float:
	case op:
		Add: lhs + rhs
		Sub: lhs - rhs
		Divide: lhs / rhs
		Modulo:
			panic("Cannot modulo floating point values")
		Multiply: lhs * rhs

fn eval_comparison_float(op: bc.ComparisonOperator, lhs: float, rhs: float) -> bool:
	case op:
		Less: lhs < rhs
		LessEquals: lhs <= rhs
		Greater: lhs > rhs
		GreaterEquals: lhs >= rhs
		Equals: lhs == rhs
		NotEquals: lhs != rhs

# fn eval_bitop(op: bc.BitOperator, lhs: Value, rhs: Value):
# 	pass

fn eval_bitop_int64(op: bc.BitOperator, lhs: int64, rhs: int64) -> int64:
	case op:
		Shr: lhs >> rhs
		Shl: lhs << rhs
		And: lhs & rhs
		Or: lhs | rhs
		Xor: lhs ^ rhs

fn eval_bitop_int32(op: bc.BitOperator, lhs: int32, rhs: int32) -> int32:
	case op:
		Shr: lhs >> rhs
		Shl: lhs << rhs
		And: lhs & rhs
		Or: lhs | rhs
		Xor: lhs ^ rhs

fn eval_bitop_uint64(op: bc.BitOperator, lhs: uint64, rhs: uint64) -> uint64:
	case op:
		Shr: lhs >> rhs
		Shl: lhs << rhs
		And: lhs & rhs
		Or: lhs | rhs
		Xor: lhs ^ rhs

fn eval_bitop_uint32(op: bc.BitOperator, lhs: uint32, rhs: uint32) -> uint32:
	case op:
		Shr: lhs >> rhs
		Shl: lhs << rhs
		And: lhs & rhs
		Or: lhs | rhs
		Xor: lhs ^ rhs

# fn eval_bitop_uint16(op: bc.BitOperator, lhs: uint16, rhs: uint16) -> uint16:
# 	case op:
# 		Shr: lhs >> rhs
# 		Shl: lhs << rhs
# 		And: lhs & rhs
# 		Or: lhs | rhs
# 		Xor: lhs ^ rhs

# fn eval_bitop_uint8(op: bc.BitOperator, lhs: uint8, rhs: uint8) -> uint8:
# 	case op:
# 		Shr: lhs >> rhs
# 		Shl: lhs << rhs
# 		And: lhs & rhs
# 		Or: lhs | rhs
# 		Xor: lhs ^ rhs

fn eval_comparison(op: bc.ComparisonOperator, lhs: Value, rhs: Value) -> bool:
	case lhs:
		Int64(lhs_value):
			let rhs_value = int64_from_value(rhs)
			eval_comparison_int64(op, lhs: lhs_value, rhs: rhs_value)
		Int32(lhs_value):
			let rhs_value = int32_from_value(rhs)
			eval_comparison_int32(op, lhs: lhs_value, rhs: rhs_value)
		Uint64(lhs_value):
			let rhs_value = uint64_from_value(rhs)
			eval_comparison_uint64(op, lhs: lhs_value, rhs: rhs_value)
		Uint32(lhs_value):
			let rhs_value = uint32_from_value(rhs)
			eval_comparison_uint32(op, lhs: lhs_value, rhs: rhs_value)
		Float(lhs_value):
			let rhs_value = float_from_value(rhs)
			eval_comparison_float(op, lhs: lhs_value, rhs: rhs_value)
		Bool(lhs_value):
			let rhs_value = bool_from_value(rhs)
			case op:
				Equals:
					lhs_value == rhs_value
			else:
				panic("Can only compare booleans for equality")
		List(values):
			case rhs:
				Null:
					case op:
						Equals:
							false
					else:
						panic("Can only compare list to NULL")
			else:
				panic("Cannot compare list to: {value_to_string(rhs)}")
		Null:
			case op:
				Equals:
					case rhs:
						Null:
							true
					else:
						false
			else:
				panic("Can only compare NULL to NULL")
	else:
		panic("Cannot compare: {value_to_string(lhs)}")
