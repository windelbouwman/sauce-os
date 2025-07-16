"""
C code backend

Translate bytecode into C code.
"""

from std import float_to_str2
from utils import panic, log_info, log_trace
from listtype import List
from optiontype import Option
from vectype import Vector, new_vector
from strlib import str_join
import vm
import bc
from text_gen import TextGenerator
from pygenerator import escape_string, needs_escaping, escape_char

pub fn gen_c_code(program: bc.Program, output_filename: Option[str]):
	log_info("Generating C-code from bytecode")
	let g = CGenerator()
	g.out.begin(output_filename)
	g.structs = program.structs
	g.globals = program.globals
	g.extern_functions = program.extern_functions
	g.functions = program.functions

	# Runtime function prototypes:
	g.emit_runtime()
	g.gen_program(program)
	g.out.end()

struct Value:
	ty: bc.Type
	name: str

fn is_heap(ty?: bc.Type) -> bool:
	""" Test if type is heap like type """
	case ty:
		StructRef(index):
			true
		Array(element_type):
			true
		Str:
			true
		Ptr:
			true
		Function(parameter_types, return_type):
			true
	else:
		false

class CGenerator:
	# Generate C from bytecode
	pub var out: TextGenerator = TextGenerator()

	var stack: Vector[Value] = new_vector()
	var next_id: int = 1
	var local_variables: Vector[Value] = new_vector()
	var local_parameters: Vector[Value] = new_vector()
	var m_vm: vm.VirtualMachine = vm.VirtualMachine()
	pub var structs: Vector[bc.Struct] = new_vector()
	pub var globals: Vector[bc.Global] = new_vector()
	pub var functions: Vector[bc.Function] = new_vector()
	pub var extern_functions: Vector[bc.ExternFunction] = new_vector()

	pub fn emit_runtime():
		emit("#include <stddef.h>")
		emit("#include <stdint.h>")
		emit("#include <setjmp.h>")
		emit("#include <stdlib.h>")
		emit("#include \"slangrt.h\"")

	pub fn gen_program(program: bc.Program):
		vm.prepare_vm(vm: m_vm, program)

		# Struct forward declarations:
		var index = 0
		for struct_def in program.structs:
			emit("struct S{index}_{struct_def.name};")
			index += 1

		index = 0
		for struct_def in program.structs:
			# Struct definitions:
			gen_struct_def(index, struct_def)
			index += 1

		for extern_function in program.extern_functions:
			gen_extern_function_decl(extern_function)

		# Forward declarations:
		for function in program.functions:
			gen_function_decl(function)

		# Globals!
		for global in program.globals:
			gen_global(global)

		# Function definitions:
		for function in program.functions:
			gen_function(function)

	fn gen_struct_def(index: int, struct_def: bc.Struct):
		let name = "S{index}_{struct_def.name}"
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
		case extern_function.return_type:
			Some(ty):
				gen_typed_name(ty, name: "")
				write(" ")
			None:
				write("void ")
		write(extern_function.name)
		write("(")
		var index = 0
		for parameter in extern_function.parameters:
			let name = "P{index}"
			if index > 0:
				write(", ")
			gen_typed_name(ty: parameter.ty, name)
			index += 1
		write(")")
		if extern_function.no_return:
			emit("")
			emit("#if defined __GNUC__")
			emit(" __attribute__((noreturn))")
			emit("#endif")
		emit(";")

	fn gen_global(global: bc.Global):
		case global.value:
			Some(code):
				let value = vm.eval_code(vm: m_vm, code)
				let text = gen_vm_value(ty: global.ty, value)
				gen_typed_name(ty: global.ty, name: global.name)
				write(" = ")
				write(text)
			None:
				write("extern ")
				gen_typed_name(ty: global.ty, name: global.name)
		emit(";")

	fn gen_vm_value(ty: bc.Type, value: vm.Value) -> str:
		case value:
			Int(v):
				case ty:
					Int(signed, bits):
						"{v}"
					Function(parameter_types, return_type):
						let name = get_function_callee(index: v)
						name
				else:
					panic("Value must be function or int")
			Bool(v):
				if v:
					"1"
				else:
					"0"
			Float(value):
				float_to_str2(value, digits: 20)
			Str(v):
				"\"{v}\""
			Char(v):
				"'{v}'"
			List(v): # Struct
				let name = new_local_var()
				let index = case ty:
					StructRef(index):
						index
				else:
					panic("Expect struct type")
				let struct_def = structs.get(index)

				let parts: List[str] = List()
				var i = 0
				for v2 in v.values:
					parts.append(gen_vm_value(ty: struct_def.fields[i].ty, value: v2))
					i += 1

				write("struct S{index}_{struct_def.name} {name} = \{")
				for part in parts:
					write(part)
					write(", ")
				emit("\};")
				"&{name}"
		else:
			panic("Unsupported initial value")

	fn gen_function_decl(function: bc.Function):
		if function.no_return:
			emit("#if defined _MSC_VER")
			emit("__declspec(noreturn)")
			emit("#endif")
		gen_function_signature(function, fill_param: false)
		if function.no_return:
			emit("")
			emit("#if defined __GNUC__")
			emit(" __attribute__((noreturn))")
			emit("#endif")
		emit(";")

	fn gen_function_signature(function: bc.Function, fill_param: bool):
		if not function.is_pub:
			write("static ")

		case function.return_type:
			Some(ty):
				gen_typed_name(ty, name: "")
			None:
				write("void")
		write(" ")
		write(function.name)
		write("(")
		var index = 0
		for parameter in function.parameters:
			let name = "P{index}_{parameter.name}"
			if fill_param:
				local_parameters.append(Value(name, ty: parameter.ty))
			if index > 0:
				write(", ")
			gen_typed_name(ty: parameter.ty, name)
			index += 1
		write(")")

	fn gen_function(function: bc.Function):
		log_trace("Generating bytecode for {function.name}")
		next_id = 1
		local_variables = new_vector()
		local_parameters = new_vector()

		gen_function_signature(function, fill_param: true)
		emit(" \{")
		indent()
		# emit("struct localzz \{")
		# indent()
		for local in function.locals:
			let varname = new_named_local_var(name: local.name)
			gen_typed_name(ty: local.ty, name: varname)
			if is_heap(local.ty):
				write(" = NULL")
			emit(";")
			local_variables.append(Value(name: varname, ty: local.ty))
		# dedent()
		# emit("\} localz;")
		# for value in local_variables:
		#     if is_heap(value.ty):
		#         emit("localz.{value.name} = NULL;")
		# emit("int offsets[] = \{")
		# indent()
		# for value in local_variables:
		#     if is_heap(value.ty):
		#         emit("offsetof(struct localzz, {value.name}),")
		# dedent()
		# emit("-1 };")
		emit("// Localz")

		let target_labels = bc.get_target_labels(instructions: function.instructions)
		var index = 0
		for instruction in function.instructions:
			if target_labels.contains(index):
				gen_label_str(index)
				emit(":")
			gen_instruction(instruction)
			index += 1
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
				push(value)

			Literal(literal):
				case literal:
					Int(value):
						push(Value(name: "{value}", ty: bc.Type.Int(signed: true, bits: 64)))
					Float(value):
						push(Value(name: float_to_str2(value, digits: 20), ty: bc.Type.Float(bits: 64)))
					Str(value):
						let varname = new_local_var()
						let ty = bc.Type.Str()
						gen_typed_name(ty, name: varname)
						emit(" = \"{escape_string(value)}\";")
						push(Value(name: varname, ty))
					Bool(value):
						if value:
							push(Value(name: "1", ty: bc.Type.Bool()))
						else:
							push(Value(name: "0", ty: bc.Type.Bool()))
					Char(value):
						let text = if needs_escaping(c: value):
							"'{escape_char(c: value)}'"
						else:
							"'{value}'"
						push(Value(name: text, ty: bc.Type.Char()))
					Null:
						push(Value(name: "0", ty: bc.Type.Ptr()))

			Jump(label):
				gen_goto(label)

			JumpIf(label1, label2):
				let condition = pop()
				emit("if ({condition.name})")
				gen_goto(label1)
				emit("else")
				gen_goto(label2)

			SetupTry(try_label, except_label):
				let bufname = "ebuf{try_label}"
				emit("slang_exception_handler_t {bufname};")
				emit("{bufname}.prev = g_except_hook;")
				emit("g_except_hook = &{bufname};")
				emit("if (setjmp(g_except_hook->buf) == 0)")
				gen_goto(try_label)
				emit("else")
				gen_goto(except_label)

			Raise:
				let value = pop()
				emit("g_except_value = {value.name};")
				emit("longjmp(g_except_hook->buf, 1);")

			PopTry:
				emit("g_except_hook = g_except_hook->prev;")

			DecRef(index):
				let varname = local_variables.get(index)
				#if is_heap(varname.ty):
				#    emit("rt_decref({varname.name});")

			GetExceptionValue:
				let value = Value(name: "g_except_value", ty: bc.Type.Ptr())
				push(value)

			Not:
				let rhs = pop()
				let varname = new_local_var()
				let ty = rhs.ty
				write("const ")
				gen_typed_name(ty, name: varname)
				emit(" = {rhs.name} ? 0 : 1;")
				push(Value(name: varname, ty))

			Neg:
				let rhs = pop()
				let varname = new_local_var()
				let ty = rhs.ty
				write("const ")
				gen_typed_name(ty, name: varname)
				emit(" = -{rhs.name};")
				push(Value(name: varname, ty))

			Binop(op):
				let rhs = pop()
				let lhs = pop()
				let varname = new_local_var()
				let ty = lhs.ty
				write("const ")
				gen_typed_name(ty, name: varname)
				let op_txt = case op:
					Add:
						"+"
					Sub:
						"-"
					Multiply:
						"*"
					Divide:
						"/"
				write(" = ")
				write(lhs.name)
				write(op_txt)
				write(rhs.name)
				emit(";")
				push(Value(name: varname, ty))

			Comparison(op):
				let rhs = pop()
				let lhs = pop()
				let varname = new_local_var()
				let ty = bc.Type.Bool()
				write("const ")
				gen_typed_name(ty, name: varname)
				let op_txt = case op:
					Less:
						"<"
					LessEquals:
						"<="
					Greater:
						">"
					GreaterEquals:
						">="
					Equals:
						"=="
					NotEquals:
						"!="
				write(" = (")
				write(lhs.name)
				write(" ")
				write(op_txt)
				write(" ")
				write(rhs.name)
				emit(");")
				push(Value(name: varname, ty))

			Bitop(op):
				let rhs = pop()
				let lhs = pop()
				let op_txt = case op:
					And:
						"&"
					Or:
						"|"
					Xor:
						"^"
					Shr:
						">>"
					Shl:
						"<<"
				let ty = lhs.ty
				let varname = new_local_var()
				write("const ")
				gen_typed_name(ty, name: varname)
				write(" = (")
				write(lhs.name)
				write(" ")
				write(op_txt)
				write(" ")
				write(rhs.name)
				emit(");")
				push(Value(name: varname, ty))

			IntToFloat:
				let value = pop()
				let varname = new_local_var()
				let bits = 64 # TODO
				let ty = bc.Type.Float(bits)
				gen_typed_name(ty, name: varname)
				emit(" = (slang_float{bits}_t)({value.name});")
				push(Value(name: varname, ty))

			FloatToInt:
				let value = pop()
				let varname = new_local_var()
				let signed = true # TODO
				let bits = 64 # TODO
				let ty = bc.Type.Int(signed, bits)
				gen_typed_name(ty, name: varname)
				write(" = (")
				if signed:
					write("slang_int")
				else:
					write("slang_uint")
				write(str(bits))
				write("_t)(")
				write(value.name)
				emit(");")
				push(Value(name: varname, ty))

			IntCast(signed, bits):
				let value = pop()
				let varname = new_local_var()
				let ty = bc.Type.Int(signed, bits)
				gen_typed_name(ty, name: varname)
				write(" = (")
				if signed:
					write("slang_int")
				else:
					write("slang_uint")
				write(str(bits))
				write("_t)(")
				write(value.name)
				emit(");")
				push(Value(name: varname, ty))

			ToOpaque(ty3):
				let value = pop()
				let varname = new_local_var()
				let ty = bc.Type.Ptr()
				gen_typed_name(ty, name: varname)
				write(" = ")
				case ty3:
					Float(bits):
						write("SLANG_BOX_FLOAT")
						write(str(bits))
					Int(signed, bits):
						if signed:
							write("SLANG_BOX_INT")
						else:
							write("SLANG_BOX_UINT")
						write(str(bits))
					Bool:
						write("SLANG_BOX_BOOL")
					Char:
						write("SLANG_BOX_CHAR")
					Ptr:
						pass
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
				push(Value(name: varname, ty))

			FromOpaque(ty):
				# Unbox value from opaque pointer type
				let value = pop()
				let varname = new_local_var()
				gen_typed_name(ty, name: varname)
				write(" = ")
				case ty:
					Int(signed, bits):
						if signed:
							write("SLANG_UNBOX_INT")
						else:
							write("SLANG_UNBOX_UINT")
						write(str(bits))
					Float(bits):
						write("SLANG_UNBOX_FLOAT")
						write(str(bits))
					Bool:
						write("SLANG_UNBOX_BOOL")
					Str:
						write("(char*)")
					Char:
						write("SLANG_UNBOX_CHAR")
					Function(parameter_types, return_type):
						panic("Cannot unbox ptr to function")
					Array(element_type):
						write("(")
						gen_typed_name(ty: element_type, name: "")
						write("*)")
					Ptr:
						pass
					StructRef(index):
						write("(")
						gen_typed_name(ty, name: "")
						write(")")
				write("(")
				write(value.name)
				emit(");")
				let value2 = Value(name: varname, ty)
				push(value2)

			Call(index):
				if index < extern_functions.len():
					let function = extern_functions.get(index)
					let callee = function.name
					gen_call(callee, parameter_types: function.parameters, return_type: function.return_type)
				else:
					index = index - extern_functions.len()
					let function = functions.get(index)
					let callee = function.name
					gen_call(callee, parameter_types: function.parameters, return_type: function.return_type)

			CallIndirect(parameter_types, return_type):
				let target = pop()
				gen_call(callee: target.name, parameter_types, return_type)

			LocalGet(index):
				let varname = local_variables.get(index)
				push(varname)

			LocalSet(index):
				let value = pop()
				let varname = local_variables.get(index)
				write(varname.name)
				write(" = ")
				write(value.name)
				emit(";")

			GlobalGet(index):
				let global = globals.get(index)
				let name = global.name
				let ty = global.ty
				let value = Value(name, ty)
				push(value)

			GlobalSet(index):
				let value = pop()
				let name = globals.get(index).name
				write(name)
				write(" = ")
				write(value.name)
				emit(";")

			ParameterGet(index):
				let param = local_parameters.get(index)
				push(param)

			ParameterSet(index):
				let value = pop()
				let param = local_parameters.get(index)
				write(param.name)
				write(" = ")
				write(value.name)
				emit(";")

			GetAttr(index):
				let base = pop()
				let field = get_struct_field(ty: base.ty, index)
				let varname = new_local_var()
				gen_typed_name(ty: field.ty, name: varname)
				write(" = ")
				write(base.name)
				gen_field_access(index, field)
				emit(";")
				let value = Value(name: varname, ty: field.ty)
				push(value)

			SetAttr(index):
				let value = pop()
				let base = pop()
				let field = get_struct_field(ty: base.ty, index)
				write(base.name)
				gen_field_access(index, field)
				write(" = ")
				write(value.name)
				emit(";")

			GetIndex:
				let index = pop()
				let base = pop()
				let varname = new_local_var()
				let ty = bc.get_element_type_from_type(base.ty)
				gen_typed_name(ty, name: varname)
				emit(" = {base.name}[{index.name}];")
				let value = Value(name: varname, ty)
				push(value)

			SetIndex:
				let value = pop()
				let index = pop()
				let base = pop()
				emit("{base.name}[{index.name}] = {value.name};")

			Return(amount):
				if amount == 1:
					let value = pop()
					emit("return {value.name};")
				else:
					emit("return;")

			Unreachable:
				emit("SLANG_UNREACHABLE")

			LoadFunc(index):
				let callee = get_function_callee(index)
				push(Value(name: callee, ty: bc.Type.Ptr()))

			StructLiteral(index):
				# we can derive count from struct type:
				let struct_def = structs.get(index)
				let values = pop_n(count: struct_def.fields.len())
				# Malloc it!
				let varname = new_local_var()
				let ty = bc.Type.StructRef(index)  # "struct S{index}*"
				gen_typed_name(ty, name: varname)
				let name = "S{index}_{struct_def.name}"
				emit(" = rt_malloc_with_destroyer(sizeof(struct {name}), {name}_type_info);")
				var index2 = 0
				for value in values:
					let field = struct_def.fields.get(index: index2)
					emit("{varname}->f{index2}_{field.name} = {value.name};")
					index2 += 1
				push(Value(name: varname, ty))

			ArrayLiteral(size):
				let varname = new_local_var()
				let values = pop_n(count: size)
				let parts: List[str] = List()
				for value in values:
					parts.append(value.name)
				let arg_text = str_join(parts, sep: ", ")
				let ety = values.first().ty
				let ty = bc.Type.Array(ty: ety)
				gen_typed_name(ty, name: varname)
				write(" = rt_malloc({size} * sizeof(")
				gen_typed_name(ty: ety, name: "")
				emit("));")
				var index = 0
				for value in values:
					emit("{varname}[{index}] = {value.name};")
					index += 1
				push(Value(name: varname, ty))

			ArrayLiteral2(ty2):
				let size = pop()
				let varname = new_local_var()
				let ty = bc.Type.Array(ty: ty2)
				gen_typed_name(ty, name: varname)
				write(" = rt_malloc({size.name} * sizeof(")
				gen_typed_name(ty: ty2, name: "")
				emit("));")
				push(Value(name: varname, ty))

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

	fn gen_call(callee: str, parameter_types: Vector[bc.TypedName], return_type: Option[bc.Type]):
		let args = pop_n(count: parameter_types.len())
		case return_type:
			Some(ty):
				let varname = new_local_var()
				gen_typed_name(ty, name: varname)
				write(" = ")
				push(Value(name: varname, ty))
			None:
				pass
		write(callee)
		write("(")
		var first = true
		for arg in args:
			if first:
				first = false
			else:
				write(", ")
			write(arg.name)
		emit(");")

	fn gen_typed_name(ty: bc.Type, name: str):
		case ty:
			Int(signed, bits):
				if signed:
					write("slang_int")
				else:
					write("slang_uint")
				write(str(bits))
				write("_t ")
				write(name)
			Str:
				write("char* ")
				write(name)
			Char:
				write("char ")
				write(name)
			Bool:
				write("slang_bool_t ")
				write(name)
			Float(bits):
				write("slang_float{bits}_t ")
				write(name)
			Ptr:
				write("void* ")
				write(name)
			StructRef(index):
				let struct_def = structs.get(index)
				write("struct S{index}_{struct_def.name}* ")
				write(name)
			Function(parameter_types, return_type):
				case return_type:
					Some(ty):
						gen_typed_name(ty, name: "")
					None:
						write("void")
				write("(*{name})(")
				var first = true
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
				write(name)

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

	fn gen_label_str(index?: int):
		write("L")
		write(str(index))

	fn gen_goto(label?: int):
		write("goto L")
		write(str(label))
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
