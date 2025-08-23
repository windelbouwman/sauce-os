""" Generate C code directly from AST.

This is similar to the way python code is generated.

Alternative to c_gen module
"""

from std import float_to_str2
from strlib import str_join
import ast
from listtype import List
from optiontype import option_unwrap, Option
from utils import panic, log_info
from text_gen import TextGenerator
from pygenerator import escape_string, needs_escaping, escape_char


pub fn gen_c_code_v2(module_set: ast.ModuleSet, output_filename: Option[str]):
	log_info("Generating C-code")
	let g = CGenerator2()
	g.out.begin(output_filename)
	g.gen_module_set(module_set)
	g.out.end()

class CGenerator2:
	pub var out: TextGenerator = TextGenerator()

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
						var decl = gen_function_decl(function_def)
						if function_def.info.return_type.is_unreachable():
							decl = "{decl} __attribute__((noreturn))"
						emit("{decl};")

					Struct(struct_def):
						# Create struct constructor function
						if struct_def.is_union:
							panic("Unions not supported")
						let name = gen_id(id: struct_def.id)
						let parts: List[str] = List()
						for field in struct_def.fields:
							parts.append(gen_typed_name(ty: field.ty, name: field.name))
						let args = str_join(parts, sep: ", ")
						emit("struct {name}* {name}_new({args});")
				else:
					pass

	fn gen_struct_defs(module_set: ast.ModuleSet):
		for module in module_set.modules:
			for definition in module.definitions:
				case definition:
					Struct(struct_def):
						gen_struct(struct_def)
					Var(variable_def):
						let varname = gen_id(id: variable_def.variable.id)
						let typed_name = gen_typed_name(ty: variable_def.variable.ty, name: varname)
						case variable_def.value:
							Intern(value):
								write("{typed_name} = ")
								gen_expression(option_unwrap(value))
								emit(";")
							Extern(libname, initialized):
								emit("extern {typed_name};")
				else:
					pass

	fn gen_function_defs(module_set: ast.ModuleSet):
		for module in module_set.modules:
			for definition in module.definitions:
				case definition:
					Function(function_def):
						gen_function(function_def)
					Struct(struct_def):
						gen_struct_ctors(struct_def)
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
			let typed_name = gen_typed_name(ty: field.ty, name: field.name)
			emit("{typed_name};")
		dedent()
		emit("\};")
		emit("")

	fn gen_struct_ctors(struct_def: ast.StructDef):
		# Create struct constructor function
		if struct_def.is_union:
			panic("Unions not supported")

		let struct_name = gen_id(id: struct_def.id)
		let parts: List[str] = List()
		for field in struct_def.fields:
			parts.append(gen_typed_name(ty: field.ty, name: field.name))
		let args = str_join(parts, sep: ", ")
		emit("struct {struct_name}* {struct_name}_new({args}) \{")
		indent()
		emit("struct {struct_name}* X = malloc(sizeof(struct {struct_name}));")
		for field in struct_def.fields:
			emit("X->{field.name} = {field.name};")
		emit("return X;")
		dedent()
		emit("\}")
		emit("")

	fn gen_function_decl(function_def: ast.FunctionDef) -> str:
		let name = function_def.name
		let parameter_parts: List[str] = List()
		for parameter_def in function_def.parameters:
			let parameter_name = gen_id(id: parameter_def.id)
			parameter_parts.append(gen_typed_name(ty: parameter_def.ty, name: parameter_name))
		let parameter_text = str_join(parts: parameter_parts, sep: ", ")
		let return_type_text = gen_typed_name(ty: function_def.info.return_type, name: "")
		"{return_type_text} {name}({parameter_text})"

	fn gen_function(function_def: ast.FunctionDef):
		case function_def.body:
			Intern(scoped_block):
				let decl = gen_function_decl(function_def)
				emit("{decl} \{")
				if scoped_block.body.ty.is_void() or scoped_block.body.ty.is_unreachable():
					gen_block(scoped_block.body, target: Option.None())
				else:
					let res = "__SLANG_SNAG"
					indent()
					let typed_var = gen_typed_name(ty: scoped_block.body.ty, name: res)
					emit("{typed_var};")
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

	fn gen_typed_name(ty: ast.Type, name: str) -> str:
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
				parts.append(gen_typed_name(ty: param_ty.ty, name: ""))
			let param_text = str_join(parts, sep: ", ")
			gen_typed_name(ty: ret_ty, name: "(*{name})({param_text})")
		elif ty.is_void():
			"void {name}"
		elif ty.is_unreachable():
			"void {name}"
		elif ty.is_array():
			let ety = ty.get_element_type()
			# return gen_typed_name(ty: ety, name: "*{name}")
			let txt = gen_typed_name(ty: ety, name: "")
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
				gen_block(while_statement.block.body, target: Option.None())
				emit("\}")
			If(if_statement):
				gen_if_statement(if_statement, kw: "if", target)
			Loop(loop_statement):
				emit("while (1) \{")
				gen_block(loop_statement.block.body, target: Option.None())
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
							write("{res} = ")
							gen_expression(expression)
							emit(";")
						None:
							panic("gen_statement: Cannot store expression result.")
			Assignment(target, operator, value):
				case target.kind:
					GetAttr(base, attr):
						gen_expression(base)
						write("->{attr}")
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

				let op_text = case operator:
					Some(op):
						"{binary_op_to_str(op)}="
					None:
						"="
				write(" {op_text} ")
				gen_expression(value)
				emit(";")
			Let(let_statement):
				let var_name = gen_id(id: let_statement.variable.id)
				let typed_var = gen_typed_name(ty: let_statement.variable.ty, name: var_name)
				write(typed_var)
				case let_statement.value.kind:
					Stmt(statement2):
						emit(";")
						gen_statement(statement2, target: Option.Some(var_name))
				else:
					write(" = ")
					gen_expression(let_statement.value)
					emit(";")
			Break:
				emit("break;")
			Continue:
				emit("continue;")
			Return(value):
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
				gen_block(try_statement.try_block.body, target: Option.None())
				indent()
				emit("g_except_hook = {bufname}.prev;")
				dedent()
				emit("\} else \{")
				indent()
				emit("g_except_hook = {bufname}.prev;")
				let typed_var = gen_typed_name(ty: try_statement.except_type, name: param_name)
				emit("{typed_var} = g_except_value;")
				gen_statement(try_statement.except_block.body, target: Option.None())
				dedent()
				emit("\}")

			Switch(switch_statement):
				# We actually have switch in C!
				emit("switch (value) \{")
				indent()
				dedent()
				emit("\}")

			Raise(value):
				write("g_except_value = ")
				gen_expression(value)
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
				let fnc = if ty.is_float():
					"(double)"
				elif ty.is_opaque():
					"(void*)"
				elif ty.is_str():
					"(char*)"
				elif ty.is_int():
					"(intptr_t)"
				elif ty.is_bool():
					"(intptr_t)"
				elif ty.is_struct():
					let to_type2 = gen_typed_name(ty: ty, name: "")
					"({to_type2})"
				elif ty.is_char():
					"(char)"
				else:
					panic("Unsupported cast to: {ty}")
				write(fnc)
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
				write("\{ ")
				gen_expression_list(values)
				write(" \}")
			ArrayLiteral2(size, ty):
				write("calloc(")
				gen_expression(size)
				let ty_2 = gen_typed_name(ty, name: "")
				write(", sizeof({ty_2}))")
			Null:
				write("NULL")
			Box(value):
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
				elif value.ty.is_struct():
					write("(void*)")
				elif value.ty.is_opaque():
					pass
				else:
					panic("Cannot box: {value.ty}")
				write("(")
				gen_expression(value)
				write("))")
			Unbox(value, to_type):
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
				elif to_type.is_struct():
					let type_str = gen_typed_name(ty: to_type, name: "")
					write("({type_str}*)")
				else:
					panic("Cannot unbox: {to_type}")
				write("(")
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

	fn gen_id(id: ast.NodeId) -> str:
		if id.name == "main":
			"{id.name}2"
		else:
			"X{id.id}_{id.name}"

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
		And:
			"&&"
		Or:
			"||"
		Add:
			"+"
		Sub:
			"-"
		Mul:
			"*"
		Div:
			"/"
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
		BitAnd:
			"&"
		BitXor:
			"^"
		BitOr:
			"|"
		ShiftLeft:
			"<<"
		ShiftRight:
			">>"
