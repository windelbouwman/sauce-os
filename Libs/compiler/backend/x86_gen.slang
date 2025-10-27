"""X86 backend
"""

from utils import unimplemented
from logging import log_info
import sil
import mil
import x86
from listtype import List, list4, list5
from codegen import cgen, SelectionContext, Backend, Frame
from outstream import BinaryOutput
from optiontype import Option

let rax: int = 0
let rcx: int = 1
let rdx: int = 2
let rbx: int = 3
let rsp: int = 4
let rbp: int = 5
let rsi: int = 6
let rdi: int = 7

pub fn gen_x86(program: sil.Program, filename: Option[str]):
	log_info("Generating x86 instructions")
	let all_regs: List[int] = list5(rcx, rdx, rbx, rsi, rdi)
	let backend: Backend[VirtInst] = Backend:
		all_regs
		enter: enter_function
		selector: select_instruction
		to_str: vinst_to_str
		materializer: materialize
		emit_prologue: gen_prologue
		emit_epilogue: gen_epilogue
	cgen(program, backend, filename)

pub enum VirtInst:
	Entry
	RmReg(op: VirtOp, rm: VirtRm, reg: mil.Register)
	RegRm(op: VirtOp, reg: mil.Register, rm: VirtRm)
	Mov(dst: mil.Register, src: mil.Register)
	MovImm(dst: mil.Register, value: int)
	Call
	Ret

pub enum VirtRm:
	Reg(reg: mil.Register)
	StackSlot(offset: int)

pub enum VirtOp:
	Mov
	Add
	Sub

fn vinst_to_str(vi?: VirtInst) -> str:
	case vi:
		RmReg(op, rm, reg):
			"rm-reg {vop_to_str(op)}"
		RegRm(op, reg, rm):
			"reg-rm {vop_to_str(op)}"
		Mov(dst, src):
			"mov"
		MovImm(dst, value):
			"mov imm {value}"
		Ret:
			"ret"
	else:
		"virt"

fn vop_to_str(vop?: VirtOp) -> str:
	case vop:
		Mov:
			"mov"
		Add:
			"add"
		Sub:
			"sub"

fn enter_function(context: SelectionContext[VirtInst], function: sil.Function):
	let parameter_regs: List[int] = list4(rdi, rsi, rdx, rcx)
	let entry_ins = context.emit_and_get(VirtInst.Entry())
	var index = 0
	for p in function.parameters:
		let reg = context.get_value_vreg(p)
		let nr = parameter_regs.get(index)
		reg.color = nr
		entry_ins.add_def(reg)
		index += 1

fn gen_prologue(frame: Frame, out: BinaryOutput):
	x86.emit_instruction(x86.Instruction.Push(reg: rbp), out)
	x86.emit_instruction(x86.Instruction.SubRmImm(rm: x86.Rm.Reg(reg: rsp), imm: frame.stacksize), out)

	# Stack slot:
	x86.emit_instruction(x86.Instruction.MovRegRm(reg: rbp, rm: x86.Rm.Reg(reg: rsp)), out)

	# Callee save registers:
	x86.emit_instruction(x86.Instruction.Push(reg: rbx), out)

fn gen_epilogue(frame: Frame, out: BinaryOutput):
	# Callee save registers:
	x86.emit_instruction(i: x86.Instruction.Pop(reg: rbx), out)

	# Stack slot:
	x86.emit_instruction(i: x86.Instruction.AddRmImm(rm: x86.Rm.Reg(reg: rsp), imm: frame.stacksize), out)
	x86.emit_instruction(i: x86.Instruction.Pop(reg: rbp), out)
	x86.emit_instruction(i: x86.Instruction.Ret(), out)

fn select_instruction(context: SelectionContext[VirtInst], instruction: sil.Instruction):
	""" Select machine instruction based on sil operator """
	case instruction.op:
		Alloc(addr, size):
			pass
		Const(dst, value):
			let dst_reg = context.get_value_vreg(dst)
			let mov_ins = context.emit_and_get(VirtInst.MovImm(reg: dst_reg, imm: value))
			mov_ins.add_def(dst_reg)
		Binop(dst, op2, lhs, rhs):
			let dst_reg = context.get_value_vreg(dst)
			let lhs_reg = context.get_value_vreg(lhs)
			let rhs_reg = context.get_value_vreg(rhs)

			let mov_ins = context.emit_and_get(VirtInst.Mov(dst_reg, lhs_reg))
			mov_ins.add_def(dst_reg)
			mov_ins.add_use(lhs_reg)
			let op3 = case op2:
				Add:
					VirtOp.Add()
				Sub:
					VirtOp.Sub()
			else:
				unimplemented("select: {instruction}")
			let rm3 = VirtRm.Reg(reg: dst_reg)
			let op_ins = context.emit_and_get(VirtInst.RmReg(op: op3, rm3, reg3: rhs_reg))
			op_ins.add_def(dst_reg)
			op_ins.add_use(dst_reg)
			op_ins.add_use(rhs_reg)
		Call(dst, callee, arguments):
			context.emit(VirtInst.Call())
		Load(dst, addr):
			let reg = context.get_value_vreg(dst)
			let rm = load_addr(addr)
			let mov_ins = context.emit_and_get(VirtInst.RegRm(op: VirtOp.Mov(), reg, rm))
			mov_ins.add_def(reg)
		Store(addr, value):
			let rm = load_addr(addr)
			let reg = context.get_value_vreg(value)
			let mov_ins = context.emit_and_get(VirtInst.RmReg(op: VirtOp.Mov(), rm, reg))
			mov_ins.add_use(reg)
		Return(v):
			let ret_ins = context.emit_and_get(VirtInst.Ret())
			case v:
				Some(v):
					let reg = context.get_value_vreg(v)
					ret_ins.add_use(reg)
				None:
					pass
	else:
		unimplemented("select: {instruction}")

fn load_addr(addr: sil.Value) -> VirtRm:
	case addr:
		Global(name):
			unimplemented("load_addr: global value")
		Tmp(name):
			unimplemented("load_addr: tmp value")
		StackSlot(offset):
			VirtRm.StackSlot(offset)

fn materialize(minst: mil.Instruction[VirtInst], outstream: BinaryOutput):
	""" Apply selected registers, and emit selected instruction to output stream. """
	case minst.instruction:
		Entry:
			pass
		MovImm(dst, value):
			let reg2 = mat_reg(reg: dst)
			let instruction = x86.Instruction.MovRegImm(reg: reg2, imm: value)
			x86.emit_instruction(instruction, out: outstream)
		RegRm(op, reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			let instruction = case op:
				Mov:
					x86.Instruction.MovRegRm(reg: reg2, rm: rm2)
				Add:
					x86.Instruction.AddRegRm(reg: reg2, rm: rm2)
				Sub:
					x86.Instruction.SubRegRm(reg: reg2, rm: rm2)
			x86.emit_instruction(instruction, out: outstream)
		RmReg(op, rm, reg):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			let instruction = case op:
				Mov:
					x86.Instruction.MovRmReg(rm: rm2, reg: reg2)
				Add:
					x86.Instruction.AddRmReg(rm: rm2, reg: reg2)
				Sub:
					x86.Instruction.SubRmReg(rm: rm2, reg: reg2)
			x86.emit_instruction(instruction, out: outstream)
		Mov(dst, src):
			let dst_reg = mat_reg(reg: dst)
			let rm = x86.Rm.Reg(reg: mat_reg(reg: src))
			x86.emit_instruction(instruction: x86.Instruction.MovRegRm(reg: dst_reg, rm), out: outstream)
		Ret:
			# x86.emit_instruction(instruction: x86.Instruction.Ret(), out: outstream)
			if minst.uses.len() > 0:
				let src = minst.uses.get(index: 0)
				let rm = x86.Rm.Reg(reg: mat_reg(reg: src))
				x86.emit_instruction(instruction: x86.Instruction.MovRegRm(reg: rax, rm), out: outstream)
			# TODO: jump to end label?
		Call:
			x86.emit_instruction(instruction: x86.Instruction.Call(), out: outstream)

fn mat_reg(reg: mil.Register) -> int:
	reg.color

fn mat_rm(rm: VirtRm) -> x86.Rm:
	""" Materialize a Rm """
	case rm:
		Reg(reg):
			x86.Rm.Reg(reg: mat_reg(reg))
		StackSlot(offset):
			x86.Rm.MemDisp8(reg: rbp, disp: offset)
