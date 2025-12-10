"""X86 backend
"""

from utils import unimplemented, panic
from logging import log_info
from std import print
from math import modulo
import sil
import mil
import x86
from report import Report
from listtype import List, list4, list5, list8
from codegen import cgen, CodegenOptions
from isel import SelectionContext, Backend, Frame
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

let xmm0: int = 0
let xmm1: int = 1
let xmm2: int = 2
let xmm3: int = 3
let xmm4: int = 4
let xmm5: int = 5
let xmm6: int = 6
let xmm7: int = 7
let xmm8: int = 8
let xmm9: int = 9
let xmm10: int = 10
let xmm11: int = 11
let xmm12: int = 12
let xmm13: int = 13
let xmm14: int = 14
let xmm15: int = 15

pub fn gen_x86(program: sil.Program, options: CodegenOptions):
	log_info("Generating x86 instructions")
	let all_regs: List[int] = List()
	all_regs.append(rax) # Skip rax since it's special purposes
	all_regs.append(rcx)
	all_regs.append(rdx)
	all_regs.append(rbx)
	all_regs.append(rsi)
	all_regs.append(rdi)
	# Skip RBP and RSP since calling convention specific
	# all_regs.append(r8)
	# all_regs.append(r9)
	# all_regs.append(r10)
	# all_regs.append(r11)
	# all_regs.append(r12)
	# Skip 13, since it's RM encoding is specific for RIP displacement
	# all_regs.append(r14)
	# all_regs.append(r15)
	let all_regs2: List[int] = List()
	all_regs2.append(xmm0)
	all_regs2.append(xmm1)
	all_regs2.append(xmm2)
	all_regs2.append(xmm3)
	all_regs2.append(xmm4)
	all_regs2.append(xmm5)
	all_regs2.append(xmm6)
	all_regs2.append(xmm7)

	# all_regs2.append(xmm8)
	# all_regs2.append(xmm9)
	# all_regs2.append(xmm10)
	# all_regs2.append(xmm11)
	# all_regs2.append(xmm12)
	# all_regs2.append(xmm13)
	# all_regs2.append(xmm14)
	# all_regs2.append(xmm15)

	let backend: Backend[VirtInst] = Backend:
		all_regs
		all_regs2
		enter: enter_function
		selector: select_instruction
		to_str: vinst_to_str
		materializer: materialize
		emit_prologue: gen_prologue
		emit_epilogue: gen_epilogue
		fixer: x86.apply_reloc
		is_pic_reloc: x86.is_pic_reloc
		emit_data: x86.emit_data_item
	cgen(program, backend, options)

pub enum VirtInst:
	Entry
	RmReg(op: x86.Op, rm: VirtRm, reg: mil.Register)
	RegRm(op: x86.Op, reg: mil.Register, rm: VirtRm)
	MulRegRm(reg: mil.Register, rm: VirtRm)
	DivMul(op: x86.DivMulOp, rm: VirtRm)
	Mov(dst: mil.Register, src: mil.Register)
	MovImm(dst: mil.Register, value: int)
	Lea(reg: mil.Register, rm: VirtRm)
	ShiftRmReg(op: x86.ShiftOp, rm: VirtRm, amount: mil.Register)
	Push(reg: mil.Register)
	Pop(reg: mil.Register)
	CallRm(rm: VirtRm)
	CvtSi2Sd(reg: mil.Register, rm: VirtRm)
	CvttSd2Si(reg: mil.Register, rm: VirtRm)
	Ucomisd(reg: mil.Register, rm: VirtRm)
	SseOpRegRm(op: x86.SseOp, reg: mil.Register, rm: VirtRm)
	SseMovRegRm(reg: mil.Register, rm: VirtRm)
	SseMovRmReg(rm: VirtRm, reg: mil.Register)
	Actual(instruction: x86.Instruction)
	Exit

pub enum VirtRm:
	Reg(reg: mil.Register)
	StackSlot(offset: int)
	RegDisp(reg: mil.Register, offset: int)
	Global(name: str)

fn vinst_to_str(vi?: VirtInst) -> str:
	case vi:
		Entry:
			"entry"
		RmReg(op, rm, reg):
			"{x86.op_to_str(op)} {vrm_to_str(rm)}, {mil.vr_to_str(reg)}"
		RegRm(op, reg, rm):
			"{x86.op_to_str(op)} {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		MulRegRm(reg, rm):
			"imul {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		DivMul(op, rm):
			"{x86.div_mul_op_to_str(op)} {vrm_to_str(rm)}"
		Mov(dst, src):
			"mov {mil.vr_to_str(dst)}, {mil.vr_to_str(src)}"
		MovImm(dst, value):
			"mov {mil.vr_to_str(dst)}, {value}"
		Lea(dst, rm):
			"lea {mil.vr_to_str(dst)}, {vrm_to_str(rm)}"
		ShiftRmReg(op, rm, reg):
			"{x86.shift_op_to_string(op)} {vrm_to_str(rm)}, {mil.vr_to_str(reg)}"
		Push(reg):
			"push {mil.vr_to_str(reg)}"
		Pop(reg):
			"pop {mil.vr_to_str(reg)}"
		CallRm(rm):
			"call {vrm_to_str(rm)}"
		SseOpRegRm(op, reg, rm):
			"sse xx {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		CvtSi2Sd(reg, rm):
			"cvtsi2sd {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		CvttSd2Si(reg, rm):
			"cvttsd2si {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		Ucomisd(reg, rm):
			"ucomisd {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		SseMovRegRm(reg, rm):
			"movsd {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		SseMovRmReg(rm, reg):
			"movsd {vrm_to_str(rm)}, {mil.vr_to_str(reg)}"
		Actual(instruction):
			x86.instruction_to_string(instruction)
		Exit:
			"exit"

fn vrm_to_str(vrm?: VirtRm) -> str:
	case vrm:
		Reg(reg):
			mil.vr_to_str(reg)
		StackSlot(offset):
			"[rbp + {offset}]"
		RegDisp(reg, offset):
			"[{mil.vr_to_str(reg)} + {offset}]"
		Global(name):
			"[{name}]"


fn enter_function(context: SelectionContext[VirtInst], function: sil.Function):
	let parameter_regs_i64: List[int] = list4(rdi, rsi, rdx, rcx)
	var index_i64 = 0
	let parameter_regs_f64: List[int] = list8(xmm0, xmm1, xmm2, xmm3, xmm4, xmm5, xmm6, xmm7)
	var index_f64 = 0

	let entry_ins = context.emit_and_get(VirtInst.Entry())
	var offset = 0x10
	for p in function.parameters:
		let reg = context.get_value_vreg(p)
		if reg.kind == 0:
			if index_i64 < parameter_regs_i64.len():
				let nr = parameter_regs_i64.get(index: index_i64)
				index_i64 += 1
				reg.color = nr
				entry_ins.add_def(reg)
			else:
				# Load parameter from memory relative to RBP
				let rm = VirtRm.StackSlot(offset)
				let load_ins = context.emit_and_get(VirtInst.RegRm(op: x86.Op.Mov(), reg, rm))
				load_ins.add_def(reg)
				offset += 8 # TODO: not all values are size 8.
		elif reg.kind == 1:
			if index_f64 < parameter_regs_f64.len():
				let nr = parameter_regs_f64.get(index: index_f64)
				index_f64 += 1
				reg.color = nr
				entry_ins.add_def(reg)
			else:
				panic("Floating point arguments via stack not supported.")
		else:
			panic("Unsupported parameter register class")

fn gen_prologue(frame: Frame, out: BinaryOutput):
	emit(x86.Instruction.Push(reg: rbp), out)
	emit(x86.Instruction.OpRegRm(op: x86.Op.Mov(), reg: rbp, rm: x86.Rm.Reg(reg: rsp)), out)
	let imm = stack_round_up16(frame.stacksize, taken: 8)
	if imm > 0:
		emit(x86.Instruction.SubRmImm(rm: x86.Rm.Reg(reg: rsp), imm), out)

	# Callee save registers:
	emit(x86.Instruction.Push(reg: rbx), out)

fn gen_epilogue(frame: Frame, out: BinaryOutput):
	# Callee save registers:
	emit(x86.Instruction.Pop(reg: rbx), out)

	# Stack slot:
	let imm = stack_round_up16(frame.stacksize, taken: 8)
	if imm > 0:
		emit(x86.Instruction.AddRmImm(rm: x86.Rm.Reg(reg: rsp), imm), out)
	emit(x86.Instruction.Pop(reg: rbp), out)
	emit(x86.Instruction.Ret(), out)

fn stack_round_up16(value?: int, taken: int) -> int:
	""" Given the fact that we already took 'taken' bytes, round value to a multiple of 16 bytes. """
	let remainder = modulo(value: value + taken, divisor: 16)
	if remainder > 0:
		value + 16 - remainder
	else:
		value

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

			if dst_reg.kind == 0:
				case op2:
					Add:
						move(context, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(op: x86.Op.Add(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Sub:
						move(context, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(op: x86.Op.Sub(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Mul:
						move(context, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.MulRegRm(reg: dst_reg, rm: VirtRm.Reg(reg: rhs_reg)))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Div:
						let rax_reg = context.get_pre_colored(color: rax, kind: 0)
						let rdx_reg = context.get_pre_colored(color: rdx, kind: 0)
						move(context, dst: rax_reg, src: lhs_reg)
						let cqo_ins = context.emit_and_get(VirtInst.Actual(x86.Instruction.Cqo()))
						cqo_ins.add_use(rax_reg)
						cqo_ins.add_def(rdx_reg)
						cqo_ins.add_def(rax_reg)
						let op_ins = context.emit_and_get(VirtInst.DivMul(op: x86.DivMulOp.IDiv(), rm: VirtRm.Reg(reg: rhs_reg)))
						op_ins.add_use(rdx_reg)
						op_ins.add_use(rax_reg)
						op_ins.add_use(rhs_reg)
						op_ins.add_def(rax_reg)
						op_ins.add_clobber(rdx_reg)
						move(context, dst: dst_reg, src: rax_reg)
			elif dst_reg.kind == 1:
				let sse_op = case op2:
					Add:
						x86.SseOp.Add()
					Sub:
						x86.SseOp.Sub()
					Mul:
						x86.SseOp.Mul()
					Div:
						x86.SseOp.Div()
				move(context, dst: dst_reg, src: lhs_reg)
				let op_ins = context.emit_and_get(VirtInst.SseOpRegRm(op: sse_op, reg3: dst_reg, rm: VirtRm.Reg(reg: rhs_reg)))
				op_ins.add_def(dst_reg)
				op_ins.add_use(dst_reg)
				op_ins.add_use(rhs_reg)
			else:
				panic("Binop not implemented for register class: {dst_reg.kind}")
		Bitop(dst, op, lhs, rhs):
			let dst_reg = context.get_value_vreg(dst)
			let lhs_reg = context.get_value_vreg(lhs)
			let rhs_reg = context.get_value_vreg(rhs)
			if dst_reg.kind == 0:
				case op:
					And:
						move(context, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(op: x86.Op.And(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Or:
						move(context, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(op: x86.Op.Or(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Xor:
						move(context, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(op: x86.Op.Xor(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Shl:
						let rcx_reg = context.get_pre_colored(color: rcx, kind: 0)
						move(context, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.ShiftRmReg(op: x86.ShiftOp.Shl(), rm: VirtRm.Reg(dst_reg), reg: rhs_reg))
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
						op_ins.add_clobber(rcx_reg)
						op_ins.add_def(dst_reg)
					Shr:
						let rcx_reg = context.get_pre_colored(color: rcx, kind: 0)
						move(context, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.ShiftRmReg(op: x86.ShiftOp.Shr(), rm: VirtRm.Reg(dst_reg), reg: rhs_reg))
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
						op_ins.add_clobber(rcx_reg)
						op_ins.add_def(dst_reg)
					Sar:
						let rcx_reg = context.get_pre_colored(color: rcx, kind: 0)
						move(context, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.ShiftRmReg(op: x86.ShiftOp.Sar(), rm: VirtRm.Reg(dst_reg), reg: rhs_reg))
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
						op_ins.add_clobber(rcx_reg)
						op_ins.add_def(dst_reg)
			else:
				unimplemented("bit-op on non-integer register class")
		Call(dst, callee, arguments):
			# Move arguments in proper locations:
			let parameter_regs_i64: List[int] = list4(rdi, rsi, rdx, rcx)
			var p_index_i64 = 0
			let parameter_regs_f64: List[int] = list8(xmm0, xmm1, xmm2, xmm3, xmm4, xmm5, xmm6, xmm7)
			var p_index_f64 = 0
			let p_regs: List[mil.Register] = List()

			let mem_args: List[mil.Register] = List()

			for arg in arguments:
				let a_reg = context.get_value_vreg(arg)
				if a_reg.kind == 0:
					if p_index_i64 < parameter_regs_i64.len():
						let nr = parameter_regs_i64.get(index: p_index_i64)
						p_index_i64 += 1
						let p_reg = context.get_pre_colored(color: nr, kind: a_reg.kind)
						move(context, dst: p_reg, src: a_reg)
						p_regs.append(p_reg)
					else:
						mem_args.append(a_reg)
				elif a_reg.kind == 1:
					if p_index_f64 < parameter_regs_f64.len():
						let nr = parameter_regs_f64.get(index: p_index_f64)
						p_index_f64 += 1
						let p_reg = context.get_pre_colored(color: nr, kind: a_reg.kind)
						move(context, dst: p_reg, src: a_reg)
						p_regs.append(p_reg)
					else:
						panic("Unsupported: float registers via stack")
				else:
					panic("Unknown register class")
			var used_stack_size = mem_args.len() * 8
			let mis_align = modulo(value: used_stack_size, divisor: 16)
			if mis_align != 0:
				let padding = 16 - mis_align
				context.emit(VirtInst.Actual(x86.Instruction.SubRmImm(rm: x86.Rm.Reg(rsp), imm: padding)))
				used_stack_size += padding
			for mem_arg_reg in mem_args.reversed():
				let push_ins = context.emit_and_get(VirtInst.Push(mem_arg_reg))
				push_ins.add_use(mem_arg_reg)
			let call_ins = case callee:
				Global(target):
					context.emit_and_get(VirtInst.Actual(instruction: x86.Instruction.Call(target)))
				Ptr(base):
					let base_reg = context.get_value_vreg(base)
					let rm = VirtRm.Reg(reg: base_reg)
					let call_ins = context.emit_and_get(VirtInst.CallRm(rm))
					call_ins.add_use(base_reg)
					call_ins
			else:
				unimplemented("Call indirect")
			for p_reg in p_regs:
				call_ins.add_use(p_reg)
			# add register clobber information:
			let clobber_regs: List[int] = list5(rax, rcx, rdx, rdi, rsi) #, r8, r9, r10, r11)
			# let clobber_regs2: List[int] = list5(rax, rcx, rdx, rdi, rsi) #, r8, r9, r10, r11)
			for clobber_reg_nr in clobber_regs:
				call_ins.add_clobber(context.get_pre_colored(color: clobber_reg_nr, kind: 0))
			# we also clobber xmm0 .. xmm15
			var reg_nr = 0
			while reg_nr < 16:
				call_ins.add_clobber(context.get_pre_colored(color: reg_nr, kind: 1))
				reg_nr += 1
			case dst:
				Some(dst_value):
					let ret_reg = context.get_value_vreg(dst_value)
					if ret_reg.kind == 0:
						let convention_reg = context.get_pre_colored(color: rax, kind: 0)
						call_ins.add_def(convention_reg)
						move(context, dst: ret_reg, src: convention_reg)
					elif ret_reg.kind == 1:
						let convention_reg = context.get_pre_colored(color: xmm0, kind: 1)
						call_ins.add_def(convention_reg)
						move(context, dst: ret_reg, src: convention_reg)
					else:
						panic("Invalid return register class")
				None:
					pass
			if used_stack_size > 0:
				context.emit(VirtInst.Actual(x86.Instruction.AddRmImm(rm: x86.Rm.Reg(rsp), imm: used_stack_size)))
		GetAddress(dst, address):
			let reg = context.get_value_vreg(dst)
			let rm = load_addr(context, address)
			let mov_ins = context.emit_and_get(VirtInst.Lea(reg, rm))
			mov_ins.add_def(reg)
		Load(dst, address):
			let reg = context.get_value_vreg(dst)
			let rm = load_addr(context, address)
			if reg.kind == 0:
				let mov_ins = context.emit_and_get(VirtInst.RegRm(op: x86.Op.Mov(), reg, rm))
				mov_ins.add_def(reg)
				add_rm_uses(mov_ins, rm)
			elif reg.kind == 1:
				let mov_ins = context.emit_and_get(VirtInst.SseMovRegRm(reg, rm))
				mov_ins.add_def(reg)
				add_rm_uses(mov_ins, rm)
			else:
				panic("Load: Unknown register class")
		Store(address, value):
			let rm = load_addr(context, address)
			let reg = context.get_value_vreg(value)
			if reg.kind == 0:
				let mov_ins = context.emit_and_get(VirtInst.RmReg(op: x86.Op.Mov(), rm, reg))
				mov_ins.add_use(reg)
				add_rm_uses(mov_ins, rm)
			elif reg.kind == 1:
				let mov_ins = context.emit_and_get(VirtInst.SseMovRmReg(rm, reg))
				mov_ins.add_use(reg)
				add_rm_uses(mov_ins, rm)
			else:
				panic("Store: Unknown register class")
		Convert(dst, value):
			let dst_reg = context.get_value_vreg(dst)
			let value_reg = context.get_value_vreg(value)
			case dst.ty:
				PTR:
					unimplemented("Convert to ptr")
				F64:
					case value.ty:
						PTR:
							unimplemented("Convert ptr to f64")
						F64:
							unimplemented("Convert f64 to f64")
						I64:
							let rm = VirtRm.Reg(value_reg)
							let conv_ins = context.emit_and_get(VirtInst.CvtSi2Sd(reg: dst_reg, rm))
							conv_ins.add_def(dst_reg)
							conv_ins.add_use(value_reg)
				I64:
					case value.ty:
						PTR:
							unimplemented("Convert PTR to i64")
						F64:
							let rm = VirtRm.Reg(value_reg)
							let conv_ins = context.emit_and_get(VirtInst.CvttSd2Si(reg: dst_reg, rm))
							conv_ins.add_def(dst_reg)
							conv_ins.add_use(value_reg)
						I64:
							unimplemented("Convert i64 to i64")
		Jump(label):
			context.emit(VirtInst.Actual(instruction: x86.Instruction.Jmp(label)))
		JumpIf(lhs, condition, rhs, label1, label2):
			let lhs_reg = context.get_value_vreg(lhs)
			let rhs_reg = context.get_value_vreg(rhs)
			if lhs_reg.kind == 0:
				let rm3 = VirtRm.Reg(reg: lhs_reg)
				let cmp_ins = context.emit_and_get(VirtInst.RmReg(op: x86.Op.Cmp(), rm3, reg3: rhs_reg))
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
			elif lhs_reg.kind == 1:
				let cmp_ins = context.emit_and_get(VirtInst.Ucomisd(reg: lhs_reg, rm3: VirtRm.Reg(reg: rhs_reg)))
				cmp_ins.add_use(lhs_reg)
				cmp_ins.add_use(rhs_reg)
				let cmp_op = case condition:
					Eq:
						x86.Cond.Jz()
					Neq:
						x86.Cond.Jnz()
					Gt:
						x86.Cond.Ja()
					Lt:
						x86.Cond.Jb()
					Gte:
						x86.Cond.Jae()
					Lte:
						x86.Cond.Jbe()
				context.emit(VirtInst.Actual(instruction: x86.Instruction.Jcc(cmp_op, label1)))
			else:
				panic("Unsupported register class")
			context.emit(VirtInst.Actual(instruction: x86.Instruction.Jmp(label2)))
		Return(v):
			let ret_ins = context.emit_and_get(VirtInst.Exit())
			case v:
				Some(v):
					let reg = context.get_value_vreg(v)
					ret_ins.add_use(reg)
				None:
					pass
		Halt:
			context.emit(VirtInst.Actual(instruction: x86.Instruction.Int3()))

fn add_rm_uses(minst?: mil.Instruction[VirtInst], rm: VirtRm):
	""" Add use information for RM mode """
	case rm:
		RegDisp(reg, offset):
			minst.add_use(reg)
	else:
		pass

fn move(context: SelectionContext[VirtInst], dst: mil.Register, src: mil.Register):
	let mov_ins = context.emit_and_get(VirtInst.Mov(dst, src))
	mov_ins.add_def(dst)
	mov_ins.add_use(src)
	mov_ins.is_move = true

fn load_addr(context: SelectionContext[VirtInst], address: sil.Address) -> VirtRm:
	case address:
		Global(name):
			VirtRm.Global(name)
		StackSlot(offset):
			VirtRm.StackSlot(offset - context.frame.stacksize)
		Ptr(base):
			let base_reg = context.get_value_vreg(base)
			VirtRm.RegDisp(reg: base_reg, offset: 0)

fn materialize(context: SelectionContext[VirtInst], minst: mil.Instruction[VirtInst], out: BinaryOutput):
	""" Apply selected registers, and emit selected instruction to output stream. """
	case minst.instruction:
		Entry:
			pass
		MovImm(dst, value):
			let reg2 = mat_reg(reg: dst)
			if value == 0:
				let instruction = x86.Instruction.OpRegRm(op: x86.Op.Xor(), reg: reg2, rm: x86.Rm.Reg(reg2))
				emit(instruction, out)
			elif value > 0 and value < 1000000:
				let instruction = x86.Instruction.MovRegImm32(reg: reg2, imm: value)
				emit(instruction, out)
			else:
				let instruction = x86.Instruction.MovRegImm64(reg: reg2, imm: value)
				emit(instruction, out)
		Lea(dst, rm):
			let instruction = x86.Instruction.Lea(reg: mat_reg(reg: dst), rm: mat_rm(rm))
			emit(instruction, out)
		RegRm(op, reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			let instruction = x86.Instruction.OpRegRm(op, reg: reg2, rm: rm2)
			emit(instruction, out)
		RmReg(op, rm, reg):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			let instruction = x86.Instruction.OpRmReg(op, rm: rm2, reg: reg2)
			emit(instruction, out)
		MulRegRm(reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			let instruction = x86.Instruction.MulRegRm(reg: reg2, rm: rm2)
			emit(instruction, out)
		DivMul(op, rm):
			let rhs_rm = mat_rm(rm)
			emit(x86.Instruction.DivMul(op, rm: rhs_rm), out)
		Mov(dst, src):
			if dst.color != src.color:
				let dst_reg = mat_reg(reg: dst)
				let rm = x86.Rm.Reg(reg: mat_reg(reg: src))
				if dst.kind == 0:
					emit(x86.Instruction.OpRegRm(op: x86.Op.Mov(), reg: dst_reg, rm), out)
				elif dst.kind == 1:
					emit(x86.Instruction.SseMovRegRm(reg: dst_reg, rm), out)
				else:
					panic("Move not supported for register class {dst.kind}")
		ShiftRmReg(op, rm, reg):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.OpRegRm(op: x86.Op.Mov(), reg: rcx, rm: x86.Rm.Reg(reg2)), out)
			emit(x86.Instruction.ShiftRmCl(op, rm: rm2), out)
		Push(reg):
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.Push(reg: reg2), out)
		Pop(reg):
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.Pop(reg: reg2), out)
		CallRm(rm):
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.CallRm(rm: rm2), out)
		SseOpRegRm(op, reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.SseOpRegRm(op, reg: reg2, rm: rm2), out)
		CvtSi2Sd(reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.CvtSi2Sd(reg: reg2, rm: rm2), out)
		CvttSd2Si(reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.CvttSd2Si(reg: reg2, rm: rm2), out)
		Ucomisd(reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.Ucomisd(reg: reg2, rm: rm2), out)
		SseMovRegRm(reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.SseMovRegRm(reg: reg2, rm: rm2), out)
		SseMovRmReg(rm, reg):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.SseMovRmReg(rm: rm2, reg: reg2), out)
		Exit:
			if minst.uses.len() > 0:
				let src = minst.uses.get(index: 0)
				let rm = x86.Rm.Reg(reg: mat_reg(reg: src))
				emit(x86.Instruction.OpRegRm(op: x86.Op.Mov(), reg: rax, rm), out)
			emit(x86.Instruction.Jmp(context.frame.exit_label), out)
		Actual(instruction):
			emit(instruction, out)

fn emit(instruction?: x86.Instruction, out: BinaryOutput):
	# print(x86.instruction_to_string(instruction))
	x86.emit_instruction(instruction, out)


fn mat_reg(reg: mil.Register) -> int:
	reg.color

fn mat_rm(rm: VirtRm) -> x86.Rm:
	""" Materialize a Rm """
	case rm:
		Reg(reg):
			x86.Rm.Reg(reg: mat_reg(reg))
		StackSlot(offset):
			if offset > 124 or offset < -124:
				x86.Rm.MemDisp32(reg: rbp, disp: offset)
			else:
				x86.Rm.MemDisp8(reg: rbp, disp: offset)
		RegDisp(reg, offset):
			x86.Rm.MemDisp8(reg: mat_reg(reg), disp: offset)
		Global(name):
			x86.Rm.RipDisp32(name)
