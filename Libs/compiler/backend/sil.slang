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
from optiontype import Option
from strlib import str_join
from report import Report

pub class Program:
	pub var externs: List[Extern]
	pub var functions: List[Function]
	pub var blobs: List[DataBlob]

	pub fn dump(report: Report):
		if not report.is_enabled():
			return
		report.writeln("----===========----")
		report.writeln("--- SIL program ---")
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
	pub var data: Bytes

	pub fn dump(report: Report):
		report.writeln("blob {name}")
		report.writeln("   ==> [{data.as_hex()}]")

pub class Function:
	"""A graph of control flow between blocks"""
	pub var name: str
	pub var parameters: List[Value]
	pub var stacksize: int
	pub var start: Block
	pub var blocks: List[Block]

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
	pub var instructions: List[Instruction]

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
			GetAddress(dst, address):
				"{value_to_string(dst)} = get address {address_to_string(address)}"
			Load(dst, address):
				"{value_to_string(dst)} = load {address_to_string(address)}"
			Store(address, value):
				"store {address_to_string(address)}, {value_to_string(value)}"
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
					Some(value2):
						"return {value_to_string(value2)}"
					None:
						"return"
			Halt:
				"hlt"

fn comma_sep(values: List[Value]) -> str:
	let parts: List[str] = List()
	for value in values:
		parts.append(value_to_string(value))
	str_join(parts, sep: ", ")

pub enum OpCode:
	Const(dst: Value, value: int)
	Binop(dst: Value, op: BinaryOp, lhs: Value, rhs: Value)
	GetAddress(dst: Value, addr: Address)
	Load(dst: Value, addr: Address)
	Store(addr: Address, value: Value)
	Jump(label: str)
	JumpIf(lhs: Value, condition: CompOp, rhs: Value, label1: str, label2: str)
	Call(dst: Option[Value], callee: Address, arguments: List[Value])
	Return(value: Option[Value])
	Halt

pub enum BinaryOp:
	Add
	Sub
	Mul
	Div

fn op_to_string(op?: BinaryOp) -> str:
	case op:
		Add:
			"add"
		Sub:
			"sub"
		Mul:
			"mul"
		Div:
			"div"

pub enum CompOp:
	Eq
	Neq
	Gt
	Lt
	Gte
	Lte

fn comparison_to_string(op?: CompOp) -> str:
	case op:
		Eq:
			"eq"
		Neq:
			"ne"
		Gt:
			"gt"
		Gte:
			"gte"
		Lt:
			"lt"
		Lte:
			"lte"

pub enum Value:
	Tmp(name: str)

pub enum Address:
	Global(name: str)
	StackSlot(offset: int)

pub fn value_to_string(value?: Value) -> str:
	case value:
		Tmp(name):
			"%{name}"

pub fn address_to_string(address?: Address) -> str:
	case address:
		Global(name):
			"${name}"
		StackSlot(offset):
			"[stack + {offset}]"
