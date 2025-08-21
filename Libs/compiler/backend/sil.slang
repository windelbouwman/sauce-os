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

from std import print
from bytes import Bytes
from listtype import List
from optiontype import Option
from strlib import str_join

pub class Program:
	pub var functions: List[Function]
	pub var blobs: List[DataBlob]

	pub fn dump():
		print("SIL program")
		for function in functions:
			function.dump()
		for blob in blobs:
			blob.dump()

pub class DataBlob:
	""" Data block """
	pub var name: str
	pub var data: Bytes

	pub fn dump():
		print("blob {name}")
		print("   ==> [{data.as_hex()}]")

pub class Function:
	"""A graph of control flow between blocks"""
	pub var name: str
	pub var parameters: List[Value]
	pub var start: Block
	pub var blocks: List[Block]

	pub fn to_string() -> str:
		let args = comma_sep(values: parameters)
		"function {name}({args})"

	pub fn dump():
		print("{this}")
		for block in blocks:
			block.dump()

pub class Block:
	"""A linear flow of instructions"""
	pub var name: str
	pub var instructions: List[Instruction]

	pub fn to_string() -> str:
		"  @{name}"

	pub fn dump():
		print("{this}")
		for instruction in instructions:
			print("    {instruction}")

pub class Instruction:
	pub var op: OpCode

	pub fn to_string() -> str:
		case op:
			Nop:
				"nop"
			Binop(dst, op2, lhs, rhs):
				let txt = case op2:
					Add:
						"add"
					Sub:
						"sub"
					Mul:
						"mul"
					Div:
						"div"
				"{value_to_string(dst)} = {txt} {value_to_string(lhs)}, {value_to_string(rhs)}"
			Compare(dst, op2, lhs, rhs):
				let txt = case op2:
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
				"{value_to_string(dst)} = {txt} {value_to_string(lhs)}, {value_to_string(rhs)}"
			Alloc(addr, size):
				"{value_to_string(addr)} = alloc {size}"
			Load(dst, addr):
				"{value_to_string(dst)} = load {value_to_string(addr)}"
			Store(addr, value):
				"store {value_to_string(addr)}, {value_to_string(value)}"
			Jump(label):
				"jmp @{label}"
			JumpNonZero(condition, label1, label2):
				"jmp-non-zero {value_to_string(condition)} @{label1}, @{label2}"
			Call(dst, callee, arguments):
				let args = comma_sep(values: arguments)
				let txt = "call {value_to_string(callee)}({args})"
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
	Nop
	Binop(dst: Value, op: BinaryOp, lhs: Value, rhs: Value)
	Compare(dst: Value, op: CompOp, lhs: Value, rhs: Value)
	Alloc(addr: Value, size: int)
	Load(dst: Value, addr: Value)
	Store(addr: Value, value: Value)
	Jump(label: str)
	JumpNonZero(condition: Value, label1: str, label2: str)
	Call(dst: Option[Value], callee: Value, arguments: List[Value])
	Return(value: Option[Value])
	Halt

pub enum BinaryOp:
	Add
	Sub
	Mul
	Div

pub enum CompOp:
	Eq
	Neq
	Gt
	Lt
	Gte
	Lte

pub enum Value:
	Integer(value: int)
	Tmp(name: str)
	Global(name: str)

pub fn value_to_string(value?: Value) -> str:
	case value:
		Integer(value):
			"{value}"
		Tmp(name):
			"%{name}"
		Global(name):
			"${name}"
