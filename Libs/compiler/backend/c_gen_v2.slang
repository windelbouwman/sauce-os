""" Generate C code directly from AST.

This is similar to the way python code is generated.

Alternative to c_gen module
"""

from std import float_to_str2
from strlib import str_join
import ast
from listtype import List
from optiontype import option_unwrap, Option
from utils import panic
from logging import log_info
from text_gen import TextGenerator
from pygenerator import escape_string, needs_escaping, escape_char


pub fn gen_c_code_v2(module_set: ast.ModuleSet, output_filename: Option[str]):
	log_info("Generating C-code")
	let g = CGenerator2()
	g.out.begin(output_filename)
	g.gen_module_set(module_set)
	g.out.end()

enum BlockType:
	Try
	Loop

class CGenerator2:
	pub var out: TextGenerator = TextGenerator()
	var next_id: int = 1
	var m_blocks: List[BlockType] = List()

	pub fn gen_module_set(module_set: ast.ModuleSet):
		gen_header()
		gen_forward_declarations1(module_set)
		gen_forward_declarations2(module_set)
		gen_struct_defs(module_set)
		gen_function_defs(module_set)

	fn gen_header():
		emit("#include <setjmp.h>")
		emit("#include <stdlib.h>")
		emit("#include <stdint.h>")
		emit("#include \"slangrt.h\"")

	fn gen_forward_declarations1(module_set: ast.ModuleSet):
		for module in module_set.modules:
			for definition in module.definitions:
				case definition:
					Struct(struct_def):
						let decl = gen_struct_decl(struct_def)
						emit("{decl};")
				else:
					pass

	fn gen_forward_declarations2(module_set: ast.ModuleSet):
		for module in module_set.modules:
			for definition in module.definitions:
				case definition:
					Function(function_def):
						gen_function_decl(function_def)
						if function_def.info.return_type.is_unreachable():
							write(" __attribute__((noreturn))")
						emit(";")

					Struct(struct_def):
						gen_struct_ctor_decl(struct_def)
						emit(";")
				else:
					pass

	fn gen_struct_defs(module_set: ast.ModuleSet):
		for module in module_set.modules:
			for definition in module.definitions:
				case definition:
					Struct(struct_def):
						gen_struct(struct_def)
					Var(variable_def):
						gen_variable_def(variable_def)
				else:
					pass

	fn gen_variable_def(variable_def: ast.VariableDef):
		let varname = gen_id(id: variable_def.variable.id)
		case variable_def.value:
			Intern(value):
				let text = gen_global_expression(option_unwrap(value))
				gen_typed_name(ty: variable_def.variable.ty, name: varname)
				write(" = {text}")
			Extern(libname, initialized):
				write("extern ")
				gen_typed_name(ty: variable_def.variable.ty, name: varname)
		emit(";")

	fn gen_global_expression(expression?: ast.Expression) -> str:
		case expression.kind:
			IntLiteral(value):
				"{value}"
			BoolLiteral(value):
				"1" if value else "0"
			FloatLiteral(value):
				float_to_str2(value, digits: 20)
			StringLiteral(value):
				"\"{escape_string(value)}\""
			StructLiteral(ty, values):
				let struct_def = ty.get_struct_def()
				let prefix = new_var(name: "glob")
				let name = "{prefix}_{gen_id(id: struct_def.id)}"
				let parts: List[str] = List()
				for value in values:
					parts.append(gen_global_expression(value))
				let struct_name = gen_id(id: struct_def.id)
				write("struct {struct_name} {name} = \{")
				write(str_join(parts, sep: ", "))
				emit("\};")
				"&{name}"
			FunctionRef(function_def, type_arguments):
				function_def.name
		else:
			panic("gen_global_expression: {expression} not supported")

	fn gen_function_defs(module_set: ast.ModuleSet):
		for module in module_set.modules:
			for definition in module.definitions:
				case definition:
					Function(function_def):
						gen_function(function_def)
					Struct(struct_def):
						gen_struct_ctor(struct_def)
				else:
					pass

	fn gen_struct_decl(struct_def: ast.StructDef) -> str:
		let name = gen_id(id: struct_def.id)
		"struct {name}"

	fn gen_struct(struct_def: ast.StructDef):
		let decl = gen_struct_decl(struct_def)
		emit("{decl} \{")
		indent()
		for field in struct_def.fields:
			gen_typed_name(ty: field.ty, name: field.name)
			emit(";")
		dedent()
		emit("\};")
		emit("")

	fn gen_struct_ctor_decl(struct_def: ast.StructDef):
		# Create struct constructor function
		if struct_def.is_union:
			panic("Unions not supported")
		let name = gen_id(id: struct_def.id)
		write("struct {name}* {name}_new(")
		let n = struct_def.fields.len()
		var i = 0
		for field in struct_def.fields:
			gen_typed_name(ty: field.ty, name: field.name)
			i += 1
			if i < n:
				write(", ")
		write(")")

	fn gen_struct_ctor(struct_def: ast.StructDef):
		# Create struct constructor function
		if struct_def.is_union:
			panic("Unions not supported")

		gen_struct_ctor_decl(struct_def)
		emit(" \{")
		indent()
		let struct_name = gen_id(id: struct_def.id)
		emit("struct {struct_name}* X = malloc(sizeof(struct {struct_name}));")
		for field in struct_def.fields:
			emit("X->{field.name} = {field.name};")
		emit("return X;")
		dedent()
		emit("\}")
		emit("")

	fn gen_function_decl(function_def: ast.FunctionDef):
		gen_typed_name(ty: function_def.info.return_type, name: "")
		let name = function_def.name
		write(" {name}(")
		let n = function_def.parameters.len()
		var i = 0
		for parameter_def in function_def.parameters:
			i += 1
			let parameter_name = gen_id(id: parameter_def.id)
			gen_typed_name(ty: parameter_def.ty, name: parameter_name)
			if i < n:
				write(", ")
		write(")")

	fn gen_function(function_def: ast.FunctionDef):
		case function_def.body:
			Intern(scoped_block):
				gen_function_decl(function_def)
				emit(" \{")
				if scoped_block.body.ty.is_void() or scoped_block.body.ty.is_unreachable():
					gen_block(scoped_block.body, target: Option.None())
				else:
					let res = "__SLANG_SNAG"
					indent()
					gen_typed_name(ty: scoped_block.body.ty, name: res)
					emit(";")
					dedent()
					gen_block(scoped_block.body, target: Option.Some(res))
					indent()
					emit("return {res};")
					dedent()
				emit("\}")
				emit("")
			Extern(libname):
				pass
			None:
				panic("Function declarations not supported")

	fn gen_typed_name(ty: ast.Type, name: str):
		write(gen_typed_name2(ty, name))

	fn gen_typed_name2(ty: ast.Type, name: str) -> str:
		if ty.is_int():
			let signed = ty.is_signed_int()
			let bits = ty.get_bits()
			if signed:
				"slang_int{bits}_t {name}"
			else:
				"slang_uint{bits}_t {name}"
		elif ty.is_bool():
			"slang_bool_t {name}"
		elif ty.is_str():
			"char* {name}"
		elif ty.is_float():
			let bits = ty.get_bits()
			"slang_float{bits}_t {name}"
		elif ty.is_char():
			"char {name}"
		elif ty.is_opaque():
			"void* {name}"
		elif ty.is_struct():
			let struct_def = ty.get_struct_def()
			let struct_name = gen_id(id: struct_def.id)
			"struct {struct_name}* {name}"
		elif ty.is_function_type():
			let ret_ty = ty.get_return_type()
			let parts: List[str] = List()
			for param_ty in ty.get_parameter_types():
				parts.append(gen_typed_name2(ty: param_ty.ty, name: ""))
			let param_text = str_join(parts, sep: ", ")
			gen_typed_name2(ty: ret_ty, name: "(*{name})({param_text})")
		elif ty.is_void():
			"void {name}"
		elif ty.is_unreachable():
			"void {name}"
		elif ty.is_array():
			let ety = ty.get_element_type()
			# return gen_typed_name(ty: ety, name: "*{name}")
			let txt = gen_typed_name2(ty: ety, name: "")
			"{txt}* {name}"
		else:
			panic("Type: {ty} not supported")

	fn gen_block(statement?: ast.Statement, target: Option[str]):
		indent()
		gen_statement(statement, target)
		dedent()

	fn gen_statement(statement?: ast.Statement, target: Option[str]):
		case statement.kind:
			While(while_statement):
				write("while (")
				gen_expression(while_statement.condition)
				emit(") \{")
				enter_block(BlockType.Loop())
				gen_block(while_statement.block.body, target: Option.None())
				leave_block()
				emit("\}")
			If(if_statement):
				gen_if_statement(if_statement, kw: "if", target)
			Loop(loop_statement):
				emit("while (1) \{")
				enter_block(BlockType.Loop())
				gen_block(loop_statement.block.body, target: Option.None())
				leave_block()
				emit("\}")
			Compound(body):
				let n = body.len()
				var i = 0
				for s in body:
					i += 1
					if i == n:
						gen_statement(s, target)
					else:
						gen_statement(s, target: Option.None())
			Expr(expression):
				if expression.ty.is_void() or expression.ty.is_unreachable():
					gen_expression(expression)
					emit(";")
				else:
					case target:
						Some(res):
							write(res)
							write(" = ")
							gen_expression(expression)
							emit(";")
						None:
							panic("gen_statement: Cannot store expression result.")
			Assignment(target, operator, value):
				case target.kind:
					GetAttr(base, attr):
						gen_expression(base)
						write("->")
						write(attr)
					GetIndex(base, indici):
						gen_expression(base)
						write("[")
						gen_expression_list(values: indici)
						write("]")
					VariableRef(variable):
						write(gen_id(id: variable.id))
					ParameterRef(parameter_def):
						write(gen_id(id: parameter_def.id))
				else:
					panic("Unsupported assignment target: {target}")

				write(" ")
				case operator:
					Some(op):
						write(binary_op_to_str(op))
					None:
						pass
				write("= ")
				gen_expression(value)
				emit(";")
			Let(let_statement):
				let var_name = gen_id(id: let_statement.variable.id)
				gen_typed_name(ty: let_statement.variable.ty, name: var_name)
				case let_statement.value.kind:
					Stmt(statement2):
						emit(";")
						gen_statement(statement2, target: Option.Some(var_name))
				else:
					write(" = ")
					gen_expression(let_statement.value)
					emit(";")
			Break:
				unwind_blocks(stop_on_loop: true)
				emit("break;")
			Continue:
				unwind_blocks(stop_on_loop: true)
				emit("continue;")
			Return(value):
				unwind_blocks(stop_on_loop: false)
				write("return")
				case value:
					Some(v2):
						write(" ")
						gen_expression(v2)
					None:
						pass
				emit(";")

			For(for_statement):
				panic("for-statement not supported")

			Case(case_statement):
				panic("case-statement not supported")

			Try(try_statement):
				let param_name = gen_id(id: try_statement.except_var.id)
				# Create a local variable with jmp_buf
				# Also store a backup of the global exception handler.
				let bufname = "jmp_buf_{param_name}"
				emit("slang_exception_handler_t {bufname};")
				emit("{bufname}.prev = g_except_hook;")
				emit("g_except_hook = &{bufname};")
				emit("if (setjmp(g_except_hook->buf) == 0) \{")
				enter_block(BlockType.Try())
				gen_block(try_statement.try_block.body, target: Option.None())
				leave_block()
				indent()
				emit("g_except_hook = g_except_hook->prev;")
				dedent()
				emit("\} else \{")
				indent()
				emit("g_except_hook = g_except_hook->prev;")
				gen_typed_name(ty: try_statement.except_type, name: param_name)
				write(" = ")
				gen_unbox_value(to_type: try_statement.except_type)
				emit("g_except_value));")
				gen_statement(try_statement.except_block.body, target: Option.None())
				dedent()
				emit("\}")

			Switch(switch_statement):
				# We actually have switch in C!
				write("switch (")
				gen_expression(switch_statement.value)
				emit(") \{")
				indent()
				for arm in switch_statement.arms:
					write("case ")
					gen_expression(arm.value)
					emit(":")
					gen_block(arm.block.body, target)
					indent()
					emit("break;")
					dedent()
				emit("default:")
				gen_block(switch_statement.default_block.body, target)
				indent()
				emit("break;")
				dedent()
				dedent()
				emit("\}")

			Raise(value):
				write("g_except_value = ")
				gen_box_value(value)
				emit(";")
				emit("longjmp(g_except_hook->buf, 1);")

			Unreachable:
				emit("__builtin_unreachable();")

			Pass:
				pass

	fn gen_if_statement(if_statement: ast.IfStatement, kw: str, target: Option[str]):
		write("{kw} (")
		gen_expression(if_statement.condition)
		emit(") \{")
		gen_block(if_statement.true_block.body, target)
		case if_statement.false_block.body.kind:
			Pass:
				emit("\}")
			If(if_statement2):
				gen_if_statement(if_statement: if_statement2, kw: "\} else if", target)
		else:
			emit("\} else \{")
			gen_block(if_statement.false_block.body, target)
			emit("\}")

	fn enter_block(bt?: BlockType):
		m_blocks.prepend(bt)

	fn leave_block():
		m_blocks.drop_front()

	fn unwind_blocks(stop_on_loop: bool):
		for bt in m_blocks:
			case bt:
				Loop:
					if stop_on_loop:
						break
				Try:
					emit("g_except_hook = g_except_hook->prev;")

	fn gen_expression(expression?: ast.Expression):
		# TODO/TBD: optional parenthesis?
		let parens = true
		case expression.kind:
			Binop(binop):
				write("(")
				gen_expression(binop.lhs)
				let op = binary_op_to_str(op: binop.op)
				write(" {op} ")
				gen_expression(binop.rhs)
				write(")")
			Unop(op, rhs):
				case op:
					Minus:
						write("-")
						gen_expression(rhs)
					Not:
						write("(")
						gen_expression(rhs)
						write(" ? 0 : 1)")
			Call(call):
				gen_expression(call.callee)
				let values: List[ast.Expression] = List()
				for argument in call.arguments:
					values.append(argument.value)
				write("(")
				gen_expression_list(values)
				write(")")
			GetAttr(base, name):
				gen_expression(base)
				write("->{name}")
			GetIndex(base, indici):
				gen_expression(base)
				write("[")
				gen_expression_list(values: indici)
				write("]")
			TypeCast(ty, value):
				write("(")
				if ty.is_float():
					write("(double)")
				elif ty.is_opaque():
					write("(void*)")
				elif ty.is_str():
					write("(char*)")
				elif ty.is_int():
					write("(intptr_t)")
				elif ty.is_bool():
					write("(intptr_t)")
				elif ty.is_struct():
					write("(")
					gen_typed_name(ty: ty, name: "")
					write(")")
				elif ty.is_char():
					write("(char)")
				else:
					panic("Unsupported cast to: {ty}")
				write("(")
				gen_expression(value)
				write("))")
			ParameterRef(parameter_def):
				write(gen_id(id: parameter_def.id))
			FunctionRef(function_def, type_arguments):
				write(function_def.name)
			VariableRef(variable):
				write(gen_id(id: variable.id))
			IntLiteral(value):
				write("{value}")
			FloatLiteral(value):
				write(float_to_str2(value, digits: 20))
			BoolLiteral(value):
				write("1" if value else "0")
			StringLiteral(value):
				write("\"{escape_string(value)}\"")
			CharLiteral(value):
				if needs_escaping(c: value):
					write("'{escape_char(c: value)}'")
				else:
					write("'{value}'")
			StructLiteral(ty, values):
				let struct_def = ty.get_struct_def()
				let name = gen_id(id: struct_def.id)
				write("{name}_new(")
				gen_expression_list(values)
				write(")")
			ArrayLiteral(values):
				let n = values.len()
				let ety = expression.ty.get_element_type()
				write("(tmp_array_lit = calloc({n}, sizeof(")
				gen_typed_name(ty: ety, name: "")
				write("))")
				var i = 0
				for value in values:
					write(", ((")
					gen_typed_name(ty: ety, name: "")
					write("*)tmp_array_lit)[{i}] = ")
					gen_expression(value)
					i += 1
				write(", tmp_array_lit)")
			ArrayLiteral2(size, ty):
				write("calloc(")
				gen_expression(size)
				write(", sizeof(")
				gen_typed_name(ty, name: "")
				write("))")
			Null:
				write("NULL")
			Box(value):
				gen_box_value(value)
			Unbox(value, to_type):
				gen_unbox_value(to_type)
				gen_expression(value)
				write("))")
			If(if_expression):
				write("(")
				gen_expression(if_expression.condition)
				write(" ? ")
				gen_expression(if_expression.true_value)
				write(" : ")
				gen_expression(if_expression.false_value)
				write(")")
		else:
			panic("Unsupported expression: {expression}")

	fn gen_expression_list(values: List[ast.Expression]):
		let n = values.len()
		var i = 0
		for value in values:
			i += 1
			gen_expression(value)
			if i < n:
				write(", ")

	fn gen_box_value(value: ast.Expression):
		write("(")
		if value.ty.is_int():
			let signed = value.ty.is_signed_int()
			let bits = value.ty.get_bits()
			if signed:
				write("SLANG_BOX_INT")
			else:
				write("SLANG_BOX_UINT")
			write(str(bits))
		elif value.ty.is_bool():
			write("SLANG_BOX_BOOL")
		elif value.ty.is_char():
			write("SLANG_BOX_CHAR")
		elif value.ty.is_str():
			write("(void*)")
		elif value.ty.is_float():
			let bits = value.ty.get_bits()
			write("SLANG_BOX_FLOAT")
			write(str(bits))
		elif value.ty.is_struct() or value.ty.is_array():
			write("(void*)")
		elif value.ty.is_opaque():
			pass
		else:
			panic("Cannot box: {value.ty}")
		write("(")
		gen_expression(value)
		write("))")

	fn gen_unbox_value(to_type: ast.Type):
		write("(")
		if to_type.is_int():
			let signed = to_type.is_signed_int()
			let bits = to_type.get_bits()
			if signed:
				write("SLANG_UNBOX_INT")
			else:
				write("SLANG_UNBOX_UINT")
			write(str(bits))
		elif to_type.is_bool():
			write("SLANG_UNBOX_BOOL")
		elif to_type.is_char():
			write("SLANG_UNBOX_CHAR")
		elif to_type.is_float():
			let bits = to_type.get_bits()
			write("SLANG_UNBOX_FLOAT")
			write(str(bits))
		elif to_type.is_str():
			write("(char*)")
		elif to_type.is_opaque():
			pass
		elif to_type.is_struct() or to_type.is_array():
			write("(")
			gen_typed_name(ty: to_type, name: "")
			write(")")
		else:
			panic("Cannot unbox: {to_type}")
		write("(")

	fn gen_id(id: ast.NodeId) -> str:
		if id.name == "main":
			"{id.name}2"
		else:
			"X{id.id}_{id.name}"

	fn new_var(name: str) -> str:
		next_id += 1
		"V{next_id}_{name}"

	fn indent():
		out.indent()

	fn dedent():
		out.dedent()

	fn emit(text?: str):
		out.emit(text)

	fn write(text?: str):
		out.write(text)


fn binary_op_to_str(op: ast.BinaryOperator) -> str:
	case op:
		And: "&&"
		Or: "||"
		Add: "+"
		Sub: "-"
		Mul: "*"
		Div: "/"
		Mod: "%"
		Less: "<"
		LessEquals: "<="
		Greater: ">"
		GreaterEquals: ">="
		Equals: "=="
		NotEquals: "!="
		BitAnd: "&"
		BitXor: "^"
		BitOr: "|"
		ShiftLeft: "<<"
		ShiftRight: ">>"
