""" Generate python code from AST.
"""

import ast
from utils import panic, log_info, unimplemented
from listtype import List
from optiontype import option_unwrap, Option
from std import float_to_str2, str_len, str_slice
from strlib import str_join
from text_gen import TextGenerator

pub fn gen_python(module_set: ast.ModuleSet, generate_runtime: bool, output_filename: Option[str]):
	log_info("Generating python code")
	let g = PyGenerator()
	g.out.begin(output_filename)
	g.generate(module_set, generate_runtime)
	g.out.end()

class PyGenerator:
	pub var out: TextGenerator = TextGenerator()
	var global_header: str = ""

	pub fn generate(module_set: ast.ModuleSet, generate_runtime: bool):
		emit("# ATTENTION: AUTOMATICALLY GENERATED PYTHON CODE AHEAD!")
		for module in module_set.modules:
			gen_module(module)
		if generate_runtime:
			emit("if __name__ == '__main__':")
			indent()
			emit("import sys")
			emit("sys.exit(main2())")
			dedent()

	pub fn gen_module(module: ast.Module):
		let global_names: List[str] = List()
		for definition in module.definitions:
			case definition:
				Var(variable_def):
					case variable_def.value:
						Intern(value):
							global_names.append(get_id(id: variable_def.variable.id))
						Extern(libname, initialized):
							pass
			else:
				pass
		if global_names.len() > 0:
			let names = str_join(parts: global_names, sep: ", ")
			global_header = "global {names}"
		else:
			global_header = ""

		for definition in module.definitions:
			gen_definition(definition)

		for definition in module.definitions:
			gen_definition_variables(definition)

	fn gen_definition(definition: ast.Definition):
		case definition:
			Mod(module):
				panic("pygen module")
			Macro(macro_def):
				pass
			Function(function_def):
				case function_def.body:
					Intern(scoped_block):
						let parameter_names: List[str] = List()
						for parameter in function_def.parameters:
							parameter_names.append(get_id(id: parameter.id))
						let params = str_join(parts: parameter_names, sep: ", ")
						emit("def {function_def.name}({params}):")
						if str_len(text: global_header) > 0:
							indent()
							emit(global_header)
							dedent()

						if scoped_block.body.ty.is_void() or scoped_block.body.ty.is_unreachable():
							gen_block(scoped_block, target: Option.None())
						else:
							let res = "__SLANG_SNAG"
							gen_block(scoped_block, target: Option.Some(res))
							indent()
							emit("return {res}")
							dedent()
						emit("")
						emit("")
					Extern(libname):
						emit("from {libname} import {function_def.name}")
					None:
						panic("Function declarations not supported")

			Struct(struct_def):
				if struct_def.is_union:
					panic("Unions not supported")
				emit("class {get_id(id: struct_def.id)}:")
				indent()
				let parameter_names: List[str] = List()
				for field in struct_def.fields:
					parameter_names.append(field.name)
				let params = str_join(parts: parameter_names, sep: ", ")
				emit("def __init__(self, {params}):")
				indent()
				for field in struct_def.fields:
					emit("self.{field.name} = {field.name}")
				dedent()
				dedent()
				emit("")
				emit("")
			Class(class_def):
				panic("class-def not supported")
			Interface(interface_def):
				panic("interface-def not supported")
			Impl(impl_def):
				panic("impl-def not supported")
			Enum(enum_def):
				panic("enum-def not supported")
			Var(variable_def):
				pass

	fn gen_definition_variables(definition: ast.Definition):
		case definition:
			Var(variable_def):
				case variable_def.value:
					Intern(value):
						emit("{get_id(id: variable_def.variable.id)} = {gen_expression(option_unwrap(value), parens: false)}")
					Extern(libname, initialized):
						emit("# external: from {libname} import {get_id(id: variable_def.variable.id)}")
		else:
			pass

	fn gen_block(block?: ast.ScopedBlock, target: Option[str]):
		indent()
		gen_statement(block.body, target)
		dedent()

	fn gen_statement(statement?: ast.Statement, target: Option[str]):
		case statement.kind:
			While(while_statement):
				emit("while {gen_expression(while_statement.condition, parens: false)}:")
				gen_block(while_statement.block, target: Option.None())
			Let(let_statement):
				let varname = get_id(id: let_statement.variable.id)
				case let_statement.value.kind:
					Stmt(statement2):
						gen_statement(statement2, target: Option.Some(varname))
				else:
					emit("{varname} = {gen_expression(let_statement.value, parens: false)}")
			If(if_statement):
				gen_if_statement(if_statement, kw: "if", target)
			Pass:
				emit("pass")
			Break:
				emit("break")
			Continue:
				emit("continue")
			Try(try_statement):
				emit("try:")
				gen_block(try_statement.try_block, target: Option.None())
				let ex_name = "ex_{get_id(id: try_statement.except_var.id)}"
				emit("except ValueError as {ex_name}:")
				indent()
				emit("{get_id(id: try_statement.except_var.id)} = {ex_name}.args[0]")
				gen_statement(try_statement.except_block.body, target: Option.None())
				dedent()
			Assignment(target, op, value):
				let op_txt = case op:
					None:
						"="
					Some(op3):
						let float_division = value.ty.is_float()
						"{binary_operator_to_str(op: op3, float_division)}="
				emit("{gen_expression(target, parens: true)} {op_txt} {gen_expression(value, parens: false)}")
			Return(value):
				case value:
					None:
						emit("return")
					Some(value2):
						emit("return {gen_expression(value2, parens: false)}")
			Raise(value):
				emit("raise ValueError({gen_expression(value, parens: false)})")
			Compound(inner):
				let n = inner.len()
				var i = 0
				for s in inner:
					i += 1
					if i == n:
						gen_statement(s, target)
					else:
						gen_statement(s, target: Option.None())
			Expr(expr):
				let txt = gen_expression(expr, parens: true)
				if expr.ty.is_void() or expr.ty.is_unreachable():
					emit(txt)
				else:
					case target:
						Some(res):
							emit("{res} = {txt}")
						None:
							panic("gen_statement: Cannot store expression result.")
			Unreachable:
				emit("raise RuntimeError('unreachable')")
		else:
			panic("gen_statement: Unsupported: {statement}")

	fn gen_if_statement(if_statement: ast.IfStatement, kw: str, target: Option[str]):
		emit("{kw} {gen_expression(if_statement.condition, parens: false)}:")
		gen_block(if_statement.true_block, target)
		case if_statement.false_block.body.kind:
			If(if2):
				gen_if_statement(if_statement: if2, kw: "elif", target)
			Pass:
				pass
		else:
			emit("else:")
			gen_block(if_statement.false_block, target)

	fn gen_expression(expression?: ast.Expression, parens: bool) -> str:
		case expression.kind:
			BoolLiteral(v):
				if v:
					"True"
				else:
					"False"
			IntLiteral(v):
				"{v}"
			StringLiteral(s):
				"\"{escape_string(s)}\""
			CharLiteral(c):
				if needs_escaping(c):
					"\"{escape_char(c)}\""
				else:
					"\"{c}\""
			Null:
				"None"
			FloatLiteral(value):
				float_to_str2(value, digits: 20)
			StructLiteral(ty, values):
				let struct_def = ty.get_struct_def()
				let name = get_id(id: struct_def.id)
				let args = gen_expression_list(expressions: values)
				"{name}({args})"
			ArrayLiteral(values):
				let args = gen_expression_list(expressions: values)
				"[{args}]"
			ArrayLiteral2(size, ty):
				let size_txt = gen_expression(size, parens: false)
				"[None] * {size_txt}"
			GetAttr(base, attr):
				let b = gen_expression(base, parens: true)
				"{b}.{attr}"
			GetIndex(base, indici):
				let b = gen_expression(base, parens: true)
				let i = gen_expression_list(expressions: indici)
				"{b}[{i}]"
			TypeCast(ty, value):
				let txt = gen_expression(value, parens: true)
				if ty.is_float():
					"float({txt})"
				elif ty.is_int():
					"int({txt})"
				else:
					panic("Cannot cast to {ty}")
			Box(value):
				gen_expression(value, parens: true)
			Unbox(value, to_type):
				gen_expression(value, parens: true)
			ParameterRef(parameter_def):
				get_id(id: parameter_def.id)
			VariableRef(variable):
				get_id(id: variable.id)
			FunctionRef(function_def, type_arguments):
				function_def.name
			Call(call):
				let expressions: List[ast.Expression] = List()
				for argument in call.arguments:
					expressions.append(argument.value)
				let argument_text = gen_expression_list(expressions)
				"{gen_expression(call.callee, parens: true)}({argument_text})"
			Unop(op, value):
				let op2 = case op:
					Not:
						"not "
					Minus:
						"-"
				let txt = "{op2}{gen_expression(value, parens: true)}"
				if parens:
					"({txt})"
				else:
					txt
			Binop(binop):
				let float_division = binop.lhs.ty.is_float()
				let op = binary_operator_to_str(op: binop.op, float_division)
				let txt = "{gen_expression(binop.lhs, parens: true)} {op} {gen_expression(binop.rhs, parens: true)}"
				if parens:
					"({txt})"
				else:
					txt
		else:
			panic("Unsupported: {expression}")

	fn gen_expression_list(expressions: List[ast.Expression]) -> str:
		let parts: List[str] = List()
		for expression in expressions:
			parts.append(gen_expression(expression, parens: false))
		str_join(parts, sep: ", ")

	fn get_id(id: ast.NodeId) -> str:
		"X{id.id}_{id.name}"

	fn emit(txt?: str):
		out.emit(txt)

	fn indent():
		out.indent()

	fn dedent():
		out.dedent()

fn binary_operator_to_str(op: ast.BinaryOperator, float_division: bool) -> str:
	case op:
		And:
			"and"
		Or:
			"or"
		Greater:
			">"
		GreaterEquals:
			">="
		Less:
			"<"
		LessEquals:
			"<="
		Equals:
			"=="
		NotEquals:
			"!="
		Add:
			"+"
		Sub:
			"-"
		Mul:
			"*"
		Div:
			if float_division:
				"/"
			else:
				"//"
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

pub fn escape_string(text?: str) -> str:
	""" Prefix double quotes and backslashes with an extra backslash """
	var res = ""
	var index = 0
	var begin = 0
	let n = str_len(text)
	while index < n:
		let c = text[index]
		if needs_escaping(c):
			if begin < index:
				res = res + str_slice(text, begin, end: index)
			res = res + escape_char(c)
			begin = index + 1
		index += 1

	if begin == 0:
		text
	else:
		if begin < index:
			res = res + str_slice(text, begin, end: index)
		res

pub fn needs_escaping(c: char) -> bool:
	if c == '\\' or c == '"' or c == '\'' or c == '\n' or c == '\r' or c == '\t':
		true
	else:
		false

pub fn escape_char(c: char) -> str:
	if c == '\n':
		"\\n"
	elif c == '\r':
		"\\r"
	elif c == '\t':
		"\\t"
	elif c == '\\':
		"\\\\"
	elif c == '\'':
		"\\'"
	elif c == '"':
		"\\\""
	else:
		unimplemented("Escape: {c}")
