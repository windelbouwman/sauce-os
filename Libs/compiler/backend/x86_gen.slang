"""
X86 backend
"""

from utils import log_info, unimplemented, panic
import sil
import mil
import x86
from codegen import cgen, SelectionContextV1, SelectionContextV2, Backend, Frame
from outstream import BinaryOutput
from optiontype import Option

# TODO:
# type SelectionContext[x86.Instruction] Ctx

pub fn gen_x86(program: sil.Program, filename: Option[str]):
	log_info("Generating x86 instructions")
	let backend: Backend = Backend:
		selector: select_instruction_v1
		# materializer: materialize
		# instruction_as_str: x86.instruction_to_string
		# to_binstream: x86.emit_instruction
		emit_prologue: gen_prologue
		emit_epilogue: gen_epilogue
	cgen(program, backend, filename)

fn emit_v1(context: SelectionContextV1, instruction?: x86.Instruction):
	x86.emit_instruction(instruction, out: context.m_outstream)

fn fetch_rm_v1(context: SelectionContextV1, value?: sil.Value) -> x86.Rm:
	case value:
		Global(name):
			unimplemented("global value")
		Tmp(name):
			let reg = context.get_reg(name)
			x86.Rm.Reg(reg)
		StackSlot(offset):
			let rbp = 5  # TODO: support global constants
			x86.Rm.MemDisp8(reg: rbp, disp: offset)

fn fetch_reg_v1(context: SelectionContextV1, value?: sil.Value) -> int:
	case value:
		Global(name):
			unimplemented("global value as reg")
		Tmp(name):
			context.get_reg(name)
		StackSlot(offset):
			unimplemented("stack slot as reg")

fn select_instruction_v1(context: SelectionContextV1, instruction: sil.Instruction):
	""" Select machine instruction based on sil operator """
	case instruction.op:
		Alloc(addr, size):
			pass
		Const(dst, value):
			let dst_reg = fetch_reg_v1(context, dst)
			emit_v1(context, x86.Instruction.MovRegImm(reg: dst_reg, imm: value))
		Binop(dst, op2, lhs, rhs):
			let dst_reg = fetch_reg_v1(context, dst)
			let lhs_rm = fetch_rm_v1(context, lhs)
			let rhs_rm = fetch_rm_v1(context, rhs)
			emit_v1(context, x86.Instruction.MovRegRm(reg: dst_reg, rm: lhs_rm))
			case op2:
				Add:
					emit_v1(context, x86.Instruction.AddRegRm(reg: dst_reg, rm: rhs_rm))
				Sub:
					emit_v1(context, x86.Instruction.SubRegRm(reg: dst_reg, rm: rhs_rm))
			else:
				unimplemented("select: {instruction}")
		Call(dst, callee, arguments):
			# emit_v1(context, x86.Instruction.Call())
			unimplemented("call")
		Load(dst, addr):
			let dst_reg = fetch_reg_v1(context, dst)
			let rm_addr = fetch_rm_v1(context, addr)
			emit_v1(context, x86.Instruction.MovRegRm(reg: dst_reg, rm: rm_addr))
		Store(addr, value):
			let rm_addr = fetch_rm_v1(context, addr)
			let r = fetch_reg_v1(context, value)
			emit_v1(context, x86.Instruction.MovRmReg(rm: rm_addr, reg: r))
		Return(v):
			case v:
				Some(v):
					let rax = 0
					let res_value = fetch_rm_v1(context, v)
					emit_v1(context, x86.Instruction.MovRegRm(reg: rax, rm: res_value))
				None:
					pass
			# TODO: Jump to epilogue
			# emit_v1(context, x86.Instruction.Ret())
	else:
		unimplemented("select: {instruction}")

fn gen_prologue(frame: Frame, out: BinaryOutput):
	let rbx = 3
	let rsp = 4
	let rbp = 5
	x86.emit_instruction(x86.Instruction.Push(reg: rbp), out)
	x86.emit_instruction(x86.Instruction.SubRmImm(rm: x86.Rm.Reg(reg: rsp), imm: frame.stacksize), out)

	# Stack slot:
	x86.emit_instruction(x86.Instruction.MovRegRm(reg: rbp, rm: x86.Rm.Reg(reg: rsp)), out)

	# Callee save registers:
	x86.emit_instruction(x86.Instruction.Push(reg: rbx), out)

fn gen_epilogue(frame: Frame, out: BinaryOutput):
	let rbx = 3
	let rsp = 4
	let rbp = 5

	# Callee save registers:
	x86.emit_instruction(i: x86.Instruction.Pop(reg: rbx), out)

	# Stack slot:
	x86.emit_instruction(i: x86.Instruction.AddRmImm(rm: x86.Rm.Reg(reg: rsp), imm: frame.stacksize), out)
	x86.emit_instruction(i: x86.Instruction.Pop(reg: rbp), out)
	x86.emit_instruction(i: x86.Instruction.Ret(), out)
