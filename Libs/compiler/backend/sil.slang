"""
SIL (slang intermediate language)

An intermediate language for an abstract register based machine.

Properties:
- SSA (static single assignment)
- Closer to hardware, but still abstract (infinite registers)
- Basic operators
- basic types, integers and floating points
- Load and store from memory

Optimizers might operate on SIL

SSA IL
Similar to QBE IL
See: https://c9x.me/compile/doc/il.html
"""

from bytes import Bytes
from listtype import List
from vectype import Vector
from optiontype import Option
from strlib import str_join
from report import Report

pub class Program:
	pub var externs: Vector[Extern]
	pub var functions: Vector[Function]
	pub var blobs: Vector[DataBlob]

	pub fn dump(report: Report):
		if not report.is_enabled():
			return
		report.heading("SIL program")
		for ext in externs:
			report.writeln(" > Import {ext.name}")
		for function in functions:
			function.dump(report)
		for blob in blobs:
			blob.dump(report)
		report.writeln("")

pub class Extern:
	pub var name: str
	# TODO: parameters?

pub class DataBlob:
	""" Data block """
	pub var name: str
	pub var is_local: bool  # Symbol visibility
	pub var readonly: bool
	pub var contents: List[BlobContent]

	pub fn dump(report: Report):
		report.writeln("blob {name}")
		if readonly:
			report.writeln("   [read-only]")
		for content in contents:
			case content:
				Raw(data):
					report.writeln("   ==> [{data.as_hex()}]")
				Ptr(name):
					report.writeln("   ==> [{name}]")

pub enum BlobContent:
	Raw(data: Bytes)
	Ptr(name: str)

pub class Function:
	"""A graph of control flow between blocks"""
	pub var name: str
	pub var parameters: Vector[Value]
	pub var stacksize: int
	pub var start: Block
	pub var blocks: Vector[Block]

	pub fn to_string() -> str:
		let args = comma_sep(values: parameters)
		"function {name}({args})"

	pub fn dump(report: Report):
		report.writeln("{this}")
		for block in blocks:
			block.dump(report)

pub class Block:
	"""A linear flow of instructions"""
	pub var name: str
	pub var instructions: Vector[Instruction]

	pub fn to_string() -> str:
		"  @{name}"

	pub fn dump(report: Report):
		report.writeln("{this}")
		for instruction in instructions:
			report.writeln("    {instruction}")

pub class Instruction:
	pub var op: OpCode

	pub fn to_string() -> str:
		case op:
			Const(dst, value):
				"{value_to_string(dst)} = {value}"
			Binop(dst, op2, lhs, rhs):
				let txt = op_to_string(op2)
				"{value_to_string(dst)} = {txt} {value_to_string(lhs)}, {value_to_string(rhs)}"
			Bitop(dst, op, lhs, rhs):
				"{value_to_string(dst)} = bitop {value_to_string(lhs)}, {value_to_string(rhs)}"
			GetAddress(dst, address):
				"{value_to_string(dst)} = get address {address_to_string(address)}"
			Load(dst, address):
				"{value_to_string(dst)} = load {address_to_string(address)}"
			Store(address, value):
				"store {address_to_string(address)}, {value_to_string(value)}"
			Convert(sx, dst, src):
				let s = "sext" if sx else "zext"
				"{value_to_string(dst)} = convert {s} {value_to_string(src)}"
			Jump(label):
				"jmp @{label}"
			JumpIf(lhs, condition, rhs, label1, label2):
				let txt = comparison_to_string(condition)
				"jmp-if {value_to_string(lhs)} {txt} {value_to_string(rhs)} => @{label1}, @{label2}"
			Call(dst, callee, arguments):
				let args = comma_sep(values: arguments)
				let txt = "call {address_to_string(callee)}({args})"
				case dst:
					Some(target):
						"{value_to_string(target)} = {txt}"
					None:
						txt
			Return(value):
				case value:
					Some(value2): "return {value_to_string(value2)}"
					None: "return"
			Halt: "hlt"

fn comma_sep(values: Vector[Value]) -> str:
	let parts: List[str] = List()
	for value in values:
		parts.append(value_to_string(value))
	str_join(parts, sep: ", ")

pub enum OpCode:
	Const(dst: Value, value: int)
	Binop(dst: Value, op: BinaryOp, lhs: Value, rhs: Value)
	Bitop(dst: Value, op: BitwiseOp, lhs: Value, rhs: Value)
	GetAddress(dst: Value, address: Address)
	Load(dst: Value, address: Address)
	Store(address: Address, value: Value)
	Convert(sx: bool, dst: Value, src: Value)
	Jump(label: str)
	JumpIf(lhs: Value, condition: CompOp, rhs: Value, label1: str, label2: str)
	Call(dst: Option[Value], callee: Address, arguments: Vector[Value])
	Return(value: Option[Value])
	Halt

pub fn is_terminating_op(op: OpCode) -> bool:
	case op:
		Jump(label): true
		JumpIf(lhs, c, rhs, label1, label2): true
		Return(value): true
		Halt: true
	else:
		false

pub enum BinaryOp:
	Add
	Sub
	Mul
	Div
	Mod

pub enum BitwiseOp:
	And
	Or
	Xor
	Shl
	Shr
	Sar

fn op_to_string(op?: BinaryOp) -> str:
	case op:
		Add: "add"
		Sub: "sub"
		Mul: "mul"
		Div: "div"
		Mod: "mod"

pub enum CompOp:
	Eq
	Neq
	Gt
	Lt
	Gte
	Lte

fn comparison_to_string(op?: CompOp) -> str:
	case op:
		Eq: "eq"
		Neq: "ne"
		Gt: "gt"
		Gte: "gte"
		Lt: "lt"
		Lte: "lte"

pub struct Value:
	id: int
	ty: Type

pub enum Type:
	F64
	F32
	I64
	I32
	I16
	I8

pub fn type_to_string(ty?: Type) -> str:
	case ty:
		F64: "f64"
		F32: "f32"
		I64: "i64"
		I32: "i32"
		I16: "i16"
		I8: "i8"

pub enum Address:
	Global(name: str)
	StackSlot(offset: int)
	Ptr(base: Value)

pub fn value_to_string(value?: Value) -> str:
	"{type_to_string(value.ty)} %x{value.id}"

pub fn address_to_string(address?: Address) -> str:
	case address:
		Global(name): "${name}"
		StackSlot(offset): "[stack + {offset}]"
		Ptr(base): "[{value_to_string(base)}]"
