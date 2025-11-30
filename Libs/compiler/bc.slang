
from std import float_to_str
from listtype import List
from optiontype import Option
from settype import Set, new_int_set
from vectype import Vector
from utils import panic
from text_gen import TextGenerator

pub struct Program:
	extern_functions: Vector[ExternFunction]
	globals: Vector[Global]
	structs: Vector[Struct]
	functions: Vector[Function]

pub struct Global:
	name: str
	ty: Type
	value: Option[Vector[Instruction]]

pub struct Struct:
	name: str
	fields: List[TypedName]

pub struct TypedName:
	ty: Type
	name: str

pub struct ExternFunction:
	name: str
	parameters: Vector[TypedName]
	return_types: Vector[Type]
	no_return: bool

pub struct Function:
	is_pub: bool
	name: str
	parameters: Vector[TypedName]
	return_types: Vector[Type]
	no_return: bool
	locals: Vector[TypedName]
	instructions: Vector[Instruction]

pub enum Type:
	Int(signed: bool, bits: int)
	Float(bits: int)
	Bool
	Str
	Char
	Ptr
	StructRef(index: int)
	Array(element_type: Type)
	Function(parameter_types: List[Type], return_types: Vector[Type])

pub fn get_element_type_from_type(ty?: Type) -> Type:
	case ty:
		Array(element_type):
			element_type
	else:
		panic("get_element_type_from_type: No array type")

pub enum Instruction:
	Nop
	Dup  # Duplicate stack top
	Swap

	Literal(literal: LiteralValue)

	Not
	Neg

	Binop(op: BinaryOperator)
	Bitop(op: BitOperator)

	IntCast(signed: bool, bits: int)
	IntToFloat
	FloatToInt

	ToOpaque(ty: Type)
	FromOpaque(ty: Type)

	Jump(label: int)  # Unconditional jump
	JumpIf(op: ComparisonOperator, label1: int, label2: int)
	Call(index: int)
	CallIndirect(parameters: Vector[TypedName], return_types: Vector[Type])  # Call function pointer, on top of stack
	Return(n_values: int)
	DecRef(index: int)
	Unreachable

	LocalGet(index: int)
	LocalSet(index: int)
	ParameterGet(index: int)
	ParameterSet(index: int)
	GetAttr(index: int)
	SetAttr(index: int)
	GetIndex
	SetIndex

	GlobalGet(index: int)
	GlobalSet(index: int)

	LoadFunc(index: int)

	StructLiteral(struct_index: int)
	ArrayLiteral(ty: Type)

pub fn get_target_labels(instructions: Vector[Instruction]) -> Set[int]:
	""" Get a set of labels to which is being jumped """
	let target_labels = new_int_set()
	for instruction in instructions:
		case instruction:
			Jump(index):
				target_labels.add(index)
			JumpIf(op, index1, index2):
				target_labels.add(index1)
				target_labels.add(index2)
		else:
			pass
	target_labels

pub enum LiteralValue:
	Int(value: int)
	Str(value: str)
	Float(value: float)
	Bool(value: bool)
	Char(value: char)
	Null

pub enum BinaryOperator:
	Add
	Sub
	Divide
	Multiply

pub enum ComparisonOperator:
	Less
	LessEquals
	Greater
	GreaterEquals
	Equals
	NotEquals

pub enum BitOperator:
	Shr
	Shl
	Xor
	And
	Or

pub fn literal_to_string(literal?: LiteralValue) -> str:
	case literal:
		Int(value):
			"int({value})"
		Float(value):
			"float({float_to_str(value)})"
		Str(value):
			"str('{value}')"
		Bool(value):
			if value:
				"bool(true)"
			else:
				"bool(false)"
		Char(value):
			"char('{value}')"
		Null:
			"Null"

pub fn instruction_to_string(instruction?: Instruction) -> str:
	case instruction:
		Nop:
			"nop"
		Dup:
			"dup"
		Swap:
			"swap"
		Literal(literal):
			literal_to_string(literal)
		Jump(v):
			"jump({v})"
		JumpIf(op, v1, v2):
			let op2 = comparison_to_string(op)
			"jump-if({op2}, {v1}, {v2})"
		Not:
			"not"
		Neg:
			"neg"
		Binop(op):
			binop_to_string(op)
		Bitop(op):
			bitop_to_string(op)
		IntCast(signed, bits):
			if signed:
				"to-int{bits}"
			else:
				"to-uint{bits}"
		IntToFloat:
			"int-to-float"
		FloatToInt:
			"float-to-int"
		ToOpaque(t):
			"?-to-opaque"
		FromOpaque(t):
			"opaque-to-?"
		Call(index):
			"call({index})"
		CallIndirect(parameter_types, return_type):
			"call-indirect({parameter_types.len()})"
		Return(v):
			"return({v})"
		Unreachable:
			"unreachable"
		DecRef(index):
			"dec ref {index}"
		LocalGet(index):
			"local-get({index})"
		LocalSet(index):
			"local-set({index})"
		GlobalGet(index):
			"global-get({index})"
		GlobalSet(index):
			"global-set({index})"
		ParameterGet(index):
			"parameter-get({index})"
		ParameterSet(index):
			"parameter-set({index})"
		GetAttr(index):
			"get-attr({index})"
		SetAttr(index):
			"set-attr({index})"
		GetIndex:
			"get-index"
		SetIndex:
			"set-index"
		LoadFunc(index):
			"load-func({index})"
		StructLiteral(struct_index):
			"struct-literal(index={struct_index})"
		ArrayLiteral(ty):
			"array-literal"

fn binop_to_string(op: BinaryOperator) -> str:
	case op:
		Add:
			"add"
		Sub:
			"sub"
		Divide:
			"div"
		Multiply:
			"mul"

fn comparison_to_string(op: ComparisonOperator) -> str:
	case op:
		Less:
			"lt"
		LessEquals:
			"lte"
		GreaterEquals:
			"gte"
		Greater:
			"gt"
		Equals:
			"eq"
		NotEquals:
			"ne"

fn bitop_to_string(op: BitOperator) -> str:
	case op:
		Shr:
			"bit-shr"
		Shl:
			"bit-shr"
		Xor:
			"bit-xor"
		And:
			"bit-and"
		Or:
			"bit-or"

pub fn print_bc_program_to_file(program: Program, filename: Option[str]):
	let p = Printer()
	p.m_out.begin(output_filename: filename)
	p.m_out.m_one_tab = "  "
	p.write_program(program)
	p.m_out.end()

pub fn print_bc_program(program: Program):
	print_bc_program_to_file(program, filename: Option.None())

pub fn print_bc_instructions(instructions: Vector[Instruction]):
	Printer().write_instructions(instructions)

class Printer:
	pub var m_out: TextGenerator = TextGenerator()

	pub fn write_program(program: Program):
		emit("BYTECODE program")
		indent()
		var index = 0
		var func_index = 0

		for extern_function in program.extern_functions:
			emit("EXTERN FUNC {func_index} {extern_function.name}")
			func_index += 1

		for struct0 in program.structs:
			emit("STRUCT {index}")
			for field in struct0.fields:
				emit("-> {field.name}: {type_to_string(ty: field.ty)}")
			index += 1

		for global in program.globals:
			emit("GLOBAL {global.name} {type_to_string(global.ty)}")
			case global.value:
				Some(value):
					write_instructions(instructions: value)
				None:
					pass

		for function in program.functions:
			emit("FUNC {func_index}: {function.name}")
			indent()
			func_index += 1
			emit("PARAMETERS:")
			indent()
			for parameter in function.parameters:
				emit("> {parameter.name}: {type_to_string(ty: parameter.ty)}")
			dedent()
			emit("RETURNS:")
			for ty in function.return_types:
				emit("> {type_to_string(ty)}")
			emit("LOCALS:")
			indent()
			for local in function.locals:
				emit("> {local.name}: {type_to_string(ty: local.ty)}")
			dedent()
			emit("CODE:")
			indent()
			write_instructions(instructions: function.instructions)
			dedent()

			dedent()
		dedent()

	pub fn write_instructions(instructions: Vector[Instruction]):
		var index = 0
		for instruction in instructions:
			emit("{index}: {instruction_to_string(instruction)}")
			index += 1

	fn indent():
		m_out.indent()

	fn dedent():
		m_out.dedent()

	fn emit(text?: str):
		m_out.emit(text)

pub fn type_to_string(ty?: Type) -> str:
	case ty:
		Int(signed, bits):
			if signed:
				"int{bits}"
			else:
				"uint{bits}"
		Float(bits):
			"float{bits}"
		Bool:
			"bool"
		Ptr:
			"ptr"
		Str:
			"str"
		Char:
			"char"
		StructRef(index):
			"struct-ref({index})"
		Function(parameter_types, return_type):
			"func-ptr(...)"
		Array(element_type):
			"array({type_to_string(element_type)})"
