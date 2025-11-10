"""X86 backend
"""

from utils import unimplemented
from logging import log_info
from std import print
import sil
import mil
import x86
from report import Report
from listtype import List, list4, list5, list9
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
let r8: int = 8
let r9: int = 9
let r10: int = 10
let r11: int = 11
let r12: int = 12
let r13: int = 13
let r14: int = 14
let r15: int = 15

pub fn gen_x86(program: sil.Program, filename: Option[str], report: Report):
	log_info("Generating x86 instructions")
	let all_regs: List[int] = List()
	all_regs.append(rcx)
	all_regs.append(rdx)
	all_regs.append(rbx)
	all_regs.append(rsi)
	all_regs.append(rdi)
	# all_regs.append(r8)
	# all_regs.append(r9)
	# all_regs.append(r10)
	# all_regs.append(r11)
	# all_regs.append(r12)
	# all_regs.append(r14)
	# all_regs.append(r15)
	let backend: Backend[VirtInst] = Backend:
		all_regs
		enter: enter_function
		selector: select_instruction
		to_str: vinst_to_str
		materializer: materialize
		emit_prologue: gen_prologue
		emit_epilogue: gen_epilogue
		fixer: x86.apply_reloc
	cgen(program, backend, filename, report)

pub enum VirtInst:
	Entry
	RmReg(op: VirtOp, rm: VirtRm, reg: mil.Register)
	RegRm(op: VirtOp, reg: mil.Register, rm: VirtRm)
	Mov(dst: mil.Register, src: mil.Register)
	MovImm(dst: mil.Register, value: int)
	Lea(reg: mil.Register, rm: VirtRm)
	Actual(instruction: x86.Instruction)
	Exit

pub enum VirtRm:
	Reg(reg: mil.Register)
	StackSlot(offset: int)
	Global(name: str)

pub enum VirtOp:
	Mov
	Add
	Sub
	Cmp

fn vinst_to_str(vi?: VirtInst) -> str:
	case vi:
		Entry:
			"entry"
		RmReg(op, rm, reg):
			"{vop_to_str(op)} {vrm_to_str(rm)}, {vr_to_str(reg)}"
		RegRm(op, reg, rm):
			"{vop_to_str(op)} {vr_to_str(reg)}, {vrm_to_str(rm)}"
		Mov(dst, src):
			"mov {vr_to_str(dst)}, {vr_to_str(src)}"
		MovImm(dst, value):
			"mov {vr_to_str(dst)}, {value}"
		Lea(dst, rm):
			"lea {vr_to_str(dst)}, {vrm_to_str(rm)}"
		Actual(instruction):
			x86.instruction_to_string(instruction)
		Exit:
			"exit"

fn vrm_to_str(vrm?: VirtRm) -> str:
	case vrm:
		Reg(reg):
			vr_to_str(reg)
		StackSlot(offset):
			"[rbp + {offset}]"
		Global(name):
			"[{name}]"

fn vr_to_str(vr?: mil.Register) -> str:
	"R{vr.id}"

fn vop_to_str(vop?: VirtOp) -> str:
	case vop:
		Mov:
			"mov"
		Add:
			"add"
		Sub:
			"sub"
		Cmp:
			"cmp"

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
			# Move arguments in proper locations:
			let parameter_regs: List[int] = list4(rdi, rsi, rdx, rcx)
			let clobber_regs: List[int] = list9(rax, rcx, rdx, rdi, rsi, r8, r9, r10, r11)
			let p_regs: List[mil.Register] = List()
			var index = 0
			for arg in arguments:
				let a_reg = context.get_value_vreg(arg)
				let nr = parameter_regs.get(index)
				let p_reg = context.get_pre_colored(color: nr)
				let mov_ins = context.emit_and_get(VirtInst.Mov(dst: p_reg, src: a_reg))
				mov_ins.add_def(p_reg)
				mov_ins.add_use(a_reg)
				p_regs.append(p_reg)
				index += 1
			let call_ins = case callee:
				Global(target):
					context.emit_and_get(VirtInst.Actual(instruction: x86.Instruction.Call(target)))
			else:
				unimplemented("Call indirect")
			for p_reg in p_regs:
				call_ins.add_use(p_reg)
			# add register clobber information:
			for clobber_reg_nr in clobber_regs:
				call_ins.add_clobber(context.get_pre_colored(color: clobber_reg_nr))
			case dst:
				Some(dst_value):
					let ret_reg = context.get_value_vreg(dst_value)
					let convention_reg = context.get_pre_colored(color: rax)
					call_ins.add_def(convention_reg)
					let mov_ins = context.emit_and_get(VirtInst.Mov(dst: ret_reg, src: convention_reg))
					mov_ins.add_use(convention_reg)
					mov_ins.add_def(ret_reg)
				None:
					pass
		GetAddress(dst, address):
			let reg = context.get_value_vreg(dst)
			let rm = load_addr(address)
			let mov_ins = context.emit_and_get(VirtInst.Lea(reg, rm))
			mov_ins.add_def(reg)
		Load(dst, address):
			let reg = context.get_value_vreg(dst)
			let rm = load_addr(address)
			let mov_ins = context.emit_and_get(VirtInst.RegRm(op: VirtOp.Mov(), reg, rm))
			mov_ins.add_def(reg)
		Store(address, value):
			let rm = load_addr(address)
			let reg = context.get_value_vreg(value)
			let mov_ins = context.emit_and_get(VirtInst.RmReg(op: VirtOp.Mov(), rm, reg))
			mov_ins.add_use(reg)
		Jump(label):
			context.emit(VirtInst.Actual(instruction: x86.Instruction.Jmp(label)))
		JumpIf(lhs, condition, rhs, label1, label2):
			let lhs_reg = context.get_value_vreg(lhs)
			let rhs_reg = context.get_value_vreg(rhs)
			let rm3 = VirtRm.Reg(reg: lhs_reg)
			let cmp_ins = context.emit_and_get(VirtInst.RmReg(op: VirtOp.Cmp(), rm3, reg3: rhs_reg))
			cmp_ins.add_use(lhs_reg)
			cmp_ins.add_use(rhs_reg)
			let cmp_op = case condition:
					Eq:
						x86.Cond.Jz()
					Neq:
						x86.Cond.Jnz()
					Gt:
						x86.Cond.Jg()
					Lt:
						x86.Cond.Jl()
					Gte:
						x86.Cond.Jge()
					Lte:
						x86.Cond.Jle()
			context.emit(VirtInst.Actual(instruction: x86.Instruction.Jcc(cmp_op, label1)))
			context.emit(VirtInst.Actual(instruction: x86.Instruction.Jmp(label2)))
		Return(v):
			let ret_ins = context.emit_and_get(VirtInst.Exit())
			case v:
				Some(v):
					let reg = context.get_value_vreg(v)
					ret_ins.add_use(reg)
				None:
					pass
	else:
		unimplemented("select: {instruction}")

fn load_addr(address: sil.Address) -> VirtRm:
	case address:
		Global(name):
			VirtRm.Global(name)
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
			emit(instruction, out: outstream)
		Lea(dst, rm):
			let instruction = x86.Instruction.Lea(reg: mat_reg(reg: dst), rm: mat_rm(rm))
			emit(instruction, out: outstream)
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
				Cmp:
					x86.Instruction.CmpRegRm(reg: reg2, rm: rm2)
			emit(instruction, out: outstream)
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
				Cmp:
					x86.Instruction.CmpRmReg(rm: rm2, reg: reg2)
			emit(instruction, out: outstream)
		Mov(dst, src):
			let dst_reg = mat_reg(reg: dst)
			let rm = x86.Rm.Reg(reg: mat_reg(reg: src))
			emit(instruction: x86.Instruction.MovRegRm(reg: dst_reg, rm), out: outstream)
		Exit:
			# x86.emit_instruction(instruction: x86.Instruction.Ret(), out: outstream)
			if minst.uses.len() > 0:
				let src = minst.uses.get(index: 0)
				let rm = x86.Rm.Reg(reg: mat_reg(reg: src))
				emit(instruction: x86.Instruction.MovRegRm(reg: rax, rm), out: outstream)
			# TODO: jump to end label?
		Actual(instruction):
			emit(instruction, out: outstream)

fn emit(instruction: x86.Instruction, out: BinaryOutput):
	print(x86.instruction_to_string(instruction))
	x86.emit_instruction(instruction, out)


fn mat_reg(reg: mil.Register) -> int:
	reg.color

fn mat_rm(rm: VirtRm) -> x86.Rm:
	""" Materialize a Rm """
	case rm:
		Reg(reg):
			x86.Rm.Reg(reg: mat_reg(reg))
		StackSlot(offset):
			x86.Rm.MemDisp8(reg: rbp, disp: offset)
		Global(name):
			x86.Rm.RipDisp32(name)
