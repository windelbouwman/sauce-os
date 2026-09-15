module compiler.c_gen
"""C code backend

Translate bytecode into C code.
"""

from std import float_to_str2
from base.utils import panic
from base.logging import log_info, log_trace
from base.listtype import List
from base.settype import Set, new_str_set
from base.optiontype import Option, option_is_none
from base.fs import Path
from base.vectype import Vector, new_vector, new_vector_with_capacity
import vm
import bc
from text_gen import TextGenerator
from pygenerator import escape_string, needs_escaping, escape_char

pub fn gen_c_code(program: bc.Program, output_filename: Option[Path], create_header: bool):
	log_info("Generating C-code from bytecode")
	let out_source = TextGenerator()
	out_source.m_one_tab = "\t"
	out_source.begin(output_filename)
	let out_header = if create_header:
		let out_header = TextGenerator()
		out_header.m_one_tab = "\t"
		case output_filename:
			Some(filename):
				out_header.begin(output_filename: Option.Some(filename.with_suffix(suffix: "h")))
				let libname = filename.get_stem()
				out_header.emit("#ifndef SLANG_{libname}_H")
				out_header.emit("#define SLANG_{libname}_H")
				out_header.emit("")
				out_source.emit("#include \"{libname}.h\"")
		else:
			panic("Can only create header when a filename is given.")
		out_header
	else:
		out_source
	let g = CGenerator(out: out_source, out_source, out_header)
	g.structs = program.structs
	g.globals = program.globals
	g.extern_functions = program.extern_functions
	g.functions = program.functions

	g.gen_program(program)
	if create_header:
		out_header.emit("")
		out_header.emit("#endif")
		out_header.end()
	out_source.end()

struct Value:
	ty: bc.Type
	name: str
	owned: bool

struct Local:
	ty: bc.Type
	name: str
	writable: bool

fn is_heap(ty?: bc.Type) -> bool:
	"""Test if type is heap like type"""
	case ty:
		StructRef(index): true
		Array(element_type): true
		Str: true
		Ptr: true
	else:
		false

fn has_heap_field(struct_def: bc.Struct) -> bool:
	for field in struct_def.fields:
		if is_heap(field.ty):
			return true
	false

class CGenerator:
	# Generate C from bytecode
	var out: TextGenerator
	var out_source: TextGenerator
	var out_header: TextGenerator

	var stack: Vector[Value] = new_vector()
	var next_id: int = 1
	var local_variables: Vector[Local] = new_vector()
	var local_parameters: Vector[Value] = new_vector()
	var local_return_ptrs: Vector[Value] = new_vector()
	var m_vm: vm.VirtualMachine = vm.VirtualMachine()
	pub var structs: Vector[bc.Struct] = new_vector()
	pub var globals: Vector[bc.Global] = new_vector()
	pub var functions: Vector[bc.Function] = new_vector()
	pub var extern_functions: Vector[bc.ExternFunction] = new_vector()

	pub fn gen_program(program: bc.Program):
		vm.prepare_vm(vm: m_vm, program)

		out = out_header

		# Include external libraries
		emit("#include <stddef.h>")
		emit("#include <stdint.h>")
		emit("#include <stdlib.h>")
		emit("")

		let included_headers: Set[str] = new_str_set()
		for struct_def in program.structs:
			case struct_def.libname:
				Some(libname):
					included_headers.add(libname)
				None:
					pass
		for extern_function in program.extern_functions:
			case extern_function.libname:
				Some(libname):
					included_headers.add(libname)
				None:
					pass
		for libname in included_headers:
			emit("#include \"{libname}.h\"")
		emit("")

		# Struct forward declarations:
		for struct_def in program.structs:
			if option_is_none(struct_def.libname):
				emit("struct {struct_def.name};")

		# Struct definitions:
		for struct_def in program.structs:
			if option_is_none(struct_def.libname):
				gen_struct_def(struct_def)

		for extern_function in program.extern_functions:
			if option_is_none(extern_function.libname):
				gen_extern_function_decl(extern_function)

		# Forward declarations:
		for function in program.functions:
			gen_function_decl(function)

		out = out_source

		# Globals!
		for global in program.globals:
			gen_global(global)

		# Function definitions:
		for function in program.functions:
			gen_function(function)

	fn gen_struct_def(struct_def: bc.Struct):
		let name = struct_def.name
		emit("struct {name} \{")
		indent()

		var findex = 0
		for field in struct_def.fields:
			gen_typed_name(ty: field.ty, name: "f{findex}_{field.name}")
			emit(";")
			findex += 1
		dedent()
		emit("\};")
		emit("")

		if has_heap_field(struct_def):
			# Create struct type info for garbage collector:
			# This can be used during the mark phase of garbage collection to track pointers.
			emit("static const int {name}_type_info[] = \{")
			indent()
			findex = 0
			for field in struct_def.fields:
				if is_heap(field.ty):
					emit("   offsetof(struct {name}, f{findex}_{field.name}),")
				findex += 1
			emit("   -1,")
			dedent()
			emit("\};")

	fn gen_extern_function_decl(extern_function: bc.ExternFunction):
		if extern_function.no_return:
			emit("#if defined _MSC_VER")
			emit("__declspec(noreturn)")
			emit("#endif")
		write("extern ")
		gen_function_signature(return_types: extern_function.return_types, name: extern_function.name, parameters: extern_function.parameters, fill_param: false)
		if extern_function.no_return:
			emit("")
			emit("#if defined __GNUC__")
			emit(" __attribute__((noreturn))")
			emit("#endif")
		emit(";")

	fn gen_global(global: bc.Global):
		case global.value:
			Some(code):
				gen_typed_name(ty: global.ty, name: global.name)
				write(" = ")
				if is_heap(global.ty):
					write("NULL")
					emit(";")
					# Create init code:
					let init_func_name = "_init_{global.name}"
					emit("void __attribute__((constructor(109))) {init_func_name}() \{")
					indent()
					for instruction in code:
						gen_instruction(instruction)
					let v = pop()
					emit("{global.name} = {v.name};")
					dedent()
					emit("}")
					# IDEA: emit destructor as well!
				else:
					let value = vm.eval_code(vm: m_vm, code)
					let text = gen_vm_value(ty: global.ty, value)
					write(text)
					emit(";")
			None:
				write("extern ")
				gen_typed_name(ty: global.ty, name: global.name)
				emit(";")

	fn gen_vm_value(ty: bc.Type, value: vm.Value) -> str:
		case value:
			Int64(v):
				case ty:
					Int(signed, bits):
						"{v}"
					Function(parameter_types, return_type):
						let name = get_function_callee(index: v)
						name
				else:
					panic("Value must be function or int")
			Int32(v): "{int(v)}"
			Int16(v): "{int(v)}"
			Int8(v): "{int(v)}"
			Uint64(v): "{int(v)}"
			Uint32(v): "{int(v)}"
			Uint16(v): "{int(v)}"
			Uint8(v): "{int(v)}"
			Bool(v):
				"1" if v else "0"
			Float(value):
				float_to_str2(value, digits: 20)
			Char(v):
				"'{v}'"
		else:
			panic("Unsupported initial value")

	fn gen_function_decl(function: bc.Function):
		if function.no_return:
			emit("#if defined _MSC_VER")
			emit("__declspec(noreturn)")
			emit("#endif")
		if not function.is_pub:
			write("static ")
		gen_function_signature(return_types: function.return_types, name: function.name, parameters: function.parameters, fill_param: false)
		if function.no_return:
			emit("")
			emit("#if defined __GNUC__")
			emit(" __attribute__((noreturn))")
			emit("#endif")
		emit(";")

	fn gen_function_signature(return_types: Vector[bc.Type], name: str, parameters: Vector[bc.TypedName], fill_param: bool):
		if return_types.is_empty():
			write("void")
		else:
			let ty = return_types.get(index: 0)
			gen_typed_name(ty, name: "")
		write(" ")
		write(name)
		write("(")
		var index = 1
		var first = true
		while index < return_types.len():
			let name = "Retval_{index}"
			let ty = return_types.get(index)
			if fill_param:
				local_return_ptrs.append(Value(name, ty, owned: false))
			if first:
				first = false
			else:
				write(", ")
			gen_typed_name(ty, name: "*{name}")
			index += 1

		for parameter in parameters:
			let name = "P{index}_{parameter.name}"
			if fill_param:
				local_parameters.append(Value(name, ty: parameter.ty, owned: false))
			if first:
				first = false
			else:
				write(", ")
			gen_typed_name(ty: parameter.ty, name)
			index += 1
		write(")")

	fn gen_function(function: bc.Function):
		log_trace("Generating bytecode for {function.name}")
		next_id = 1
		local_variables = new_vector_with_capacity(capacity: function.locals.len())
		local_parameters = new_vector_with_capacity(capacity: function.parameters.len())
		local_return_ptrs = new_vector()

		gen_function_signature(return_types: function.return_types, name: function.name, parameters: function.parameters, fill_param: true)
		emit(" \{")
		indent()
		for local in function.locals:
			let varname = new_named_local_var(name: local.name)
			gen_typed_name(ty: local.ty, name: varname)
			if is_heap(local.ty):
				write(" = NULL")
			emit(";")
			local_variables.append(Local(name: varname, ty: local.ty, writable: local.writable))
		if not local_variables.is_empty():
			emit("")

		let target_labels = bc.get_target_labels(instructions: function.instructions)
		var index = uint32(0)
		for instruction in function.instructions:
			if target_labels.contains(index):
				gen_label_str(index)
				emit(":")
			gen_instruction(instruction)
			index += uint32(1)
		dedent()
		emit("}")
		emit("")

	fn gen_instruction(instruction: bc.Instruction):
		case instruction:
			Nop:
				pass

			Dup:
				let value = pop()
				push(value)
				if is_heap(value.ty) and value.owned:
					push(Value(name: value.name, ty: value.ty, owned: false))
				else:
					push(value)

			Swap:
				let value1 = pop()
				let value2 = pop()
				push(value1)
				push(value2)

			Literal(literal):
				gen_literal(literal)

			Jump(label):
				gen_goto(label)

			JumpIf(op, label1, label2):
				let rhs = pop()
				let lhs = pop()
				let op_txt = case op:
					Less: "<"
					LessEquals: "<="
					Greater: ">"
					GreaterEquals: ">="
					Equals: "=="
					NotEquals: "!="
				write("if (")
				write(lhs.name)
				write(" ")
				write(op_txt)
				write(" ")
				write(rhs.name)
				emit(")")
				gen_goto(label1)
				emit("else")
				gen_goto(label2)

			DecRef(index):
				panic("dec-ref not supported")

			Not:
				let rhs = pop()
				let ty = rhs.ty
				let varname = gen_temp_assignment(ty)
				emit("{rhs.name} ? 0 : 1;")
				push(Value(name: varname, ty, owned: false))

			Neg:
				let rhs = pop()
				let ty = rhs.ty
				let varname = gen_temp_assignment(ty)
				emit("-{rhs.name};")
				push(Value(name: varname, ty, owned: false))

			Binop(op, ty):
				let rhs = pop()
				let lhs = pop()
				let varname = gen_temp_assignment(ty)
				let op_txt = case op:
					Add: "+"
					Sub: "-"
					Multiply: "*"
					Divide: "/"
					Modulo: "%"
				write(lhs.name)
				write(op_txt)
				write(rhs.name)
				emit(";")
				push(Value(name: varname, ty, owned: false))

			Bitop(op, ty):
				let rhs = pop()
				let lhs = pop()
				let op_txt = case op:
					And: "&"
					Or: "|"
					Xor: "^"
					Shr: ">>"
					Shl: "<<"
				let varname = gen_temp_assignment(ty)
				write("(")
				write(lhs.name)
				write(" ")
				write(op_txt)
				write(" ")
				write(rhs.name)
				emit(");")
				push(Value(name: varname, ty, owned: false))

			IntToFloat(bits):
				let value = pop()
				let ty = bc.Type.Float(bits)
				let varname = gen_temp_assignment(ty)
				emit("(slang_float{bits}_t)({value.name});")
				push(Value(name: varname, ty, owned: false))

			FloatToInt(signed, bits):
				let value = pop()
				let ty = bc.Type.Int(signed, bits)
				let varname = gen_temp_assignment(ty)
				write("(")
				if signed:
					write("slang_int")
				else:
					write("slang_uint")
				write(str(bits))
				write("_t)(")
				write(value.name)
				emit(");")
				push(Value(name: varname, ty, owned: false))

			IntCast(signed, bits):
				let value = pop()
				let ty = bc.Type.Int(signed, bits)
				let varname = gen_temp_assignment(ty)
				write("(")
				if signed:
					write("slang_int")
				else:
					write("slang_uint")
				write(str(bits))
				write("_t)(")
				write(value.name)
				emit(");")
				push(Value(name: varname, ty, owned: false))

			FloatCast(bits):
				let value = pop()
				let ty = bc.Type.Float(bits)
				let varname = gen_temp_assignment(ty)
				write("(slang_float{bits}_t)(")
				write(value.name)
				emit(");")
				push(Value(name: varname, ty, owned: false))

			ToOpaque(ty3):
				gen_to_opaque(ty3)

			FromOpaque(ty):
				gen_from_opaque(ty)

			Call(index):
				if index < extern_functions.len():
					let function = extern_functions.get(index)
					let callee = function.name
					gen_call(callee, parameter_types: function.parameters, return_types: function.return_types)
				else:
					let function = functions.get(index: index - extern_functions.len())
					let callee = function.name
					gen_call(callee, parameter_types: function.parameters, return_types: function.return_types)

			CallIndirect(parameter_types, return_types):
				let target = pop()
				gen_call(callee: target.name, parameter_types, return_types)

			LocalGet(index):
				let local = local_variables.get(index)
				push(Value(name: local.name, ty: local.ty, owned: false))

			LocalSet(index):
				let value = pop()
				let local = local_variables.get(index)
				if is_heap(value.ty):
					# Increment value ref count, before decrease ref of old ref in case of self assignment:
					if not value.owned:
						inc_ref(value)
					# Release existing ref:
					write("rt_dec_ref(")
					write(local.name)
					emit(");")
				write(local.name)
				write(" = ")
				write(value.name)
				emit(";")

			GlobalGet(index):
				let global = globals.get(index)
				push(Value(name: global.name, ty: global.ty, owned: false))

			GlobalSet(index):
				let value = pop()
				let global = globals.get(index)
				if is_heap(global.ty):
					if not value.owned:
						inc_ref(value)
					# Release existing ref:
					write("rt_dec_ref(")
					write(global.name)
					emit(");")
				write(global.name)
				write(" = ")
				write(value.name)
				emit(";")

			ParameterGet(index):
				let param = local_parameters.get(index)
				push(param)

			ParameterSet(index):
				let value = pop()
				let param = local_parameters.get(index)
				if is_heap(param.ty):
					panic("Parameter writes to heap types not supported")
				write(param.name)
				write(" = ")
				write(value.name)
				emit(";")

			GetAttr(index):
				let base = pop()
				let field = get_struct_field(ty: base.ty, index)
				let ty = field.ty
				let varname = gen_temp_assignment(ty)
				write(base.name)
				gen_field_access(index, field)
				emit(";")
				var owned = false
				if is_heap(ty):
					if base.owned:
						owned = true
				let value = Value(name: varname, ty, owned)
				if owned:
					inc_ref(value)
				push(value)
				drop(base)

			SetAttr(index):
				let value = pop()
				let base = pop()
				let field = get_struct_field(ty: base.ty, index)
				if is_heap(value.ty):
					# Increment ref count:
					if not value.owned:
						inc_ref(value)
					# Release existing ref:
					write("rt_replace_owned((void**)&")
					write(base.name)
					gen_field_access(index, field)
					write(", ")
					write(value.name)
					emit(");")
				else:
					write(base.name)
					gen_field_access(index, field)
					write(" = ")
					write(value.name)
					emit(";")
				drop(base)

			GetIndex:
				let index = pop()
				let base = pop()
				let ty = bc.get_element_type_from_type(base.ty)
				let varname = gen_temp_assignment(ty)
				write(base.name)
				emit("[{index.name}];")
				let value = Value(name: varname, ty, owned: false)
				push(value)
				if base.owned:
					panic("Not impl: drop of indexed array")
				drop(base)
				# drop(index) # Scalar value

			SetIndex:
				let value = pop()
				let index = pop()
				let base = pop()
				if is_heap(value.ty):
					# Increment ref count:
					if not value.owned:
						inc_ref(value)

					write("rt_replace_owned((void**)&")
					write(base.name)
					write("[{index.name}]")
					write(", ")
					write(value.name)
					emit(");")
				else:
					write(base.name)
					emit("[{index.name}] = {value.name};")
				drop(base)
				#drop(index) a scalar anyway

			Return(amount):
				if amount > 0:
					if amount > 1:
						let values = pop_n(count: amount - 1)
						var index = 0
						for value in values:
							if not value.owned:
								inc_ref(value)
							let target = local_return_ptrs.get(index)
							emit("*{target.name} = {value.name};")
							index += 1
					let value = pop()
					if not value.owned:
						inc_ref(value)
					gen_pre_return()
					emit("return {value.name};")
				else:
					gen_pre_return()
					emit("return;")

			Unreachable:
				emit("SLANG_UNREACHABLE")

			LoadFunc(index):
				let callee = get_function_callee(index)
				push(Value(name: callee, ty: bc.Type.FuncPtr(), owned: false))

			StructLiteral(index):
				let struct_def = structs.get(index)
				let ty = bc.Type.StructRef(index)
				let varname = gen_temp_assignment(ty)
				let name = struct_def.name
				write("rt_malloc_struct(sizeof(struct {name}), ")
				if has_heap_field(struct_def):
					write("{name}_type_info")
				else:
					write("NULL")
				emit(");")
				push(Value(name: varname, ty, owned: true))

			ArrayLiteral(ty2):
				let size = pop()
				let ty = bc.Type.Array(ty: ty2)
				let varname = gen_temp_assignment(ty)
				write("rt_malloc_array({size.name}, sizeof(")
				gen_typed_name(ty: ty2, name: "")
				write("), ")
				if is_heap(ty: ty2):
					write("1")  # array of pointers
				else:
					write("0")
				emit(");")
				push(Value(name: varname, ty, owned: true))

	fn gen_literal(literal: bc.LiteralValue):
		case literal:
			Int(value):
				push(Value(name: "{value}", ty: bc.Type.Int(signed: true, bits: 64), owned: false))
			Float(value):
				push(Value(name: float_to_str2(value, digits: 20), ty: bc.Type.Float(bits: 64), owned: false))
			Str(value):
				let ty = bc.Type.Str()
				let varname = gen_temp_assignment(ty)
				emit("rt_str_new(\"{escape_string(value)}\");")
				push(Value(name: varname, ty, owned: true))
			Bool(value):
				let name = "1" if value else "0"
				push(Value(name, ty: bc.Type.Bool(), owned: false))
			Char(value):
				let text = if needs_escaping(c: value):
					"'{escape_char(c: value)}'"
				else:
					"'{value}'"
				push(Value(name: text, ty: bc.Type.Char(), owned: false))
			Null:
				push(Value(name: "0", ty: bc.Type.Ptr(), owned: false))

	fn gen_to_opaque(ty3: bc.Type):
		let value = pop()
		let ty = bc.Type.Ptr()
		let varname = gen_temp_assignment(ty)
		var owned = value.owned
		case ty3:
			Float(bits):
				write("SLANG_BOX_FLOAT")
				write(str(bits))
				owned = true
			Int(signed, bits):
				if signed:
					write("SLANG_BOX_INT")
				else:
					write("SLANG_BOX_UINT")
				owned = true
				write(str(bits))
			Bool:
				write("SLANG_BOX_BOOL")
				owned = true
			Char:
				write("SLANG_BOX_CHAR")
				owned = true
			Ptr:
				pass
			FuncPtr:
				panic("Cannot box function pointer")
			Str:
				write("(void*)")
			StructRef(index):
				write("(void*)")
			Function(parameter_types, return_type):
				panic("Cannot box function")
			Array(element_type):
				write("(void*)")
		write("(")
		write(value.name)
		emit(");")
		push(Value(name: varname, ty, owned))

	fn gen_from_opaque(ty: bc.Type):
		# Unbox value from opaque pointer type
		let value = pop()
		let varname = gen_temp_assignment(ty)
		var owned = value.owned
		case ty:
			Int(signed, bits):
				if signed:
					write("SLANG_UNBOX_INT")
				else:
					write("SLANG_UNBOX_UINT")
				write(str(bits))
				owned = false
			Float(bits):
				write("SLANG_UNBOX_FLOAT")
				write(str(bits))
				owned = false
			Bool:
				write("SLANG_UNBOX_BOOL")
				owned = false
			Str:
				write("(char*)")
			Char:
				write("SLANG_UNBOX_CHAR")
				owned = false
			Function(parameter_types, return_type):
				panic("Cannot unbox ptr to function")
			Array(element_type):
				write("(")
				gen_typed_name(ty: element_type, name: "")
				write("*)")
			Ptr:
				pass
			FuncPtr:
				panic("Cannot unbox ptr to function pointer")
			StructRef(index):
				write("(")
				gen_typed_name(ty, name: "")
				write(")")
		write("(")
		write(value.name)
		emit(");")
		if value.owned and not owned:
			dec_ref(value)
		let value2 = Value(name: varname, ty, owned)
		push(value2)

	fn get_function_callee(index: int) -> str:
		if index < extern_functions.len():
			let function = extern_functions.get(index)
			function.name
		else:
			index = index - extern_functions.len()
			let function = functions.get(index)
			function.name

	fn gen_field_access(index: int, field: bc.TypedName):
		write("->f")
		write(str(index))
		write("_")
		write(field.name)

	fn get_struct_field(ty: bc.Type, index: int) -> bc.TypedName:
		case ty:
			StructRef(struct_index):
				structs.get(index: struct_index).fields.get(index)
		else:
			panic("No struct")

	fn gen_call(callee: str, parameter_types: Vector[bc.TypedName], return_types: Vector[bc.Type]):
		let args = pop_n(count: parameter_types.len())
		let return_vars: Vector[Value] = new_vector()
		for ret_ty in return_types:
			return_vars.append(Value(name: new_local_var(), ty: ret_ty, owned: true))

		var index = 1
		while index < return_vars.len():
			let return_variable = return_vars.get(index)
			gen_typed_name(ty: return_variable.ty, name: return_variable.name)
			emit(";")
			index += 1

		if not return_vars.is_empty():
			let return_variable = return_vars.get(index: 0)
			gen_typed_name(ty: return_variable.ty, name: return_variable.name)
			write(" = ")

		write(callee)
		write("(")
		var first = true
		index = 1
		while index < return_vars.len():
			if first:
				first = false
			else:
				write(", ")
			let return_variable = return_vars.get(index)
			write("&")
			write(return_variable.name)
			index += 1
		for arg in args:
			if first:
				first = false
			else:
				write(", ")
			write(arg.name)
		emit(");")

		# After the call, drop all owned arguments
		for arg in args:
			if is_heap(arg.ty) and arg.owned:
				dec_ref(arg)

		for ret_value in return_vars:
			push(ret_value)

	fn gen_pre_return():
		for local in local_variables:
			if is_heap(local.ty):
				emit("if ({local.name} != NULL) rt_dec_ref({local.name});")

	fn gen_temp_assignment(ty: bc.Type) -> str:
		let name = new_local_var()
		gen_typed_name_2(is_const: true, ty, name)
		write(" = ")
		name

	fn gen_typed_name(ty: bc.Type, name: str):
		gen_typed_name_2(is_const: false, ty, name)

	fn gen_typed_name_2(is_const: bool, ty: bc.Type, name: str):
		case ty:
			Int(signed, bits):
				if is_const:
					write("const ")
				if signed:
					write("slang_int")
				else:
					write("slang_uint")
				write(str(bits))
				write("_t ")
				write(name)
			Str:
				write("char* ")
				if is_const:
					write("const ")
				write(name)
			Char:
				if is_const:
					write("const ")
				write("char ")
				write(name)
			Bool:
				if is_const:
					write("const ")
				write("slang_bool_t ")
				write(name)
			Float(bits):
				if is_const:
					write("const ")
				write("slang_float{bits}_t ")
				write(name)
			Ptr:
				write("void* ")
				if is_const:
					write("const ")
				write(name)
			FuncPtr:
				write("void* ")
				if is_const:
					write("const ")
				write(name)
			StructRef(index):
				let struct_def = structs.get(index)
				write("struct {struct_def.name}* ")
				if is_const:
					write("const ")
				write(name)
			Function(parameter_types, return_types):
				if return_types.is_empty():
					write("void")
				else:
					let ty = return_types.get(index: 0)
					gen_typed_name(ty, name: "")
				write("(*{name})(")
				var first = true
				var index = 1
				while index < return_types.len():
					if first:
						first = false
					else:
						write(", ")
					gen_typed_name(ty: return_types.get(index), name: "*")
					index += 1
				for p in parameter_types:
					if first:
						first = false
					else:
						write(", ")
					gen_typed_name(ty: p, name: "")
				write(")")
			Array(element_type):
				gen_typed_name(ty: element_type, name: "")
				write("* ")
				if is_const:
					write("const ")
				write(name)

	fn inc_ref(value?: Value):
		if is_heap(value.ty):
			write("rt_inc_ref(")
			write(value.name)
			emit(");")

	fn dec_ref(value?: Value):
		if is_heap(value.ty):
			write("rt_dec_ref(")
			write(value.name)
			emit(");")

	fn push(value?: Value):
		stack.append(value)

	fn pop_n(count: int) -> List[Value]:
		let values: List[Value] = List()
		while count > 0:
			let val = pop()
			values.prepend(val)
			count -= 1
		values

	fn pop() -> Value:
		stack.pop_last()

	fn drop(value?: Value):
		if is_heap(value.ty) and value.owned:
			# Warning here? This is a bit odd
			emit("// A bit odd (dec ref of dropped value):")
			# TODO?
			dec_ref(value)

	fn gen_label_str(index?: uint32):
		write("L")
		write(str(int(index)))

	fn gen_goto(label?: uint32):
		write("goto L")
		write(str(int(label)))
		emit(";")

	fn new_local_var() -> str:
		let id = new_id()
		"V{id}"

	fn new_named_local_var(name: str) -> str:
		let id = new_id()
		"V{id}_{name}"

	fn new_id() -> int:
		let id = next_id
		next_id += 1
		return id

	fn indent():
		out.indent()

	fn dedent():
		out.dedent()

	fn emit(text?: str):
		out.emit(text)

	fn write(text?: str):
		out.write(text)

	fn writeln(text?: str):
		out.writeln(text)
