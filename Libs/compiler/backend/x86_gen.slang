"""X86 backend
"""

from utils import unimplemented, panic
from logging import log_info
from vectype import Vector, vec4, vec5, vec8, new_vector_with_capacity, new_vector
from std import print
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
	let all_integer_regs: Vector[int] = new_vector()
	all_integer_regs.append(rax) # Skip rax since it's special purposes
	all_integer_regs.append(rcx)
	all_integer_regs.append(rdx)
	all_integer_regs.append(rbx)
	all_integer_regs.append(rsi)
	all_integer_regs.append(rdi)
	# Skip RBP and RSP since calling convention specific
	# all_regs.append(r8)
	# all_regs.append(r9)
	# all_regs.append(r10)
	# all_regs.append(r11)
	# all_regs.append(r12)
	# Skip 13, since it's RM encoding is specific for RIP displacement
	# all_regs.append(r14)
	# all_regs.append(r15)
	let all_float_regs: Vector[int] = new_vector()
	all_float_regs.append(xmm0)
	all_float_regs.append(xmm1)
	all_float_regs.append(xmm2)
	all_float_regs.append(xmm3)
	all_float_regs.append(xmm4)
	all_float_regs.append(xmm5)
	all_float_regs.append(xmm6)
	all_float_regs.append(xmm7)

	# all_regs2.append(xmm8)
	# all_regs2.append(xmm9)
	# all_regs2.append(xmm10)
	# all_regs2.append(xmm11)
	# all_regs2.append(xmm12)
	# all_regs2.append(xmm13)
	# all_regs2.append(xmm14)
	# all_regs2.append(xmm15)

	let all_regs: Vector[Vector[int]] = new_vector_with_capacity(capacity: 2)
	all_regs.append(all_integer_regs)
	all_regs.append(all_float_regs)

	let ctx = X86Ctx:
		parameter_regs_i64: vec4(rdi, rsi, rdx, rcx)
		parameter_regs_f64: vec8(xmm0, xmm1, xmm2, xmm3, xmm4, xmm5, xmm6, xmm7)
		clobber_regs: vec5(rax, rcx, rdx, rdi, rsi) #, r8, r9, r10, r11)
		# let clobber_regs2: List[int] = list5(rax, rcx, rdx, rdi, rsi) #, r8, r9, r10, r11)

	let backend: Backend[X86Ctx,VirtInst] = Backend:
		ctx
		bits: 64
		all_regs
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

struct X86Ctx:
	parameter_regs_i64: Vector[int]
	parameter_regs_f64: Vector[int]
	clobber_regs: Vector[int]

pub enum VirtInst:
	Entry
	RmReg(mode: x86.BitMode, op: x86.Op, rm: VirtRm, reg: mil.Register)
	RegRm(mode: x86.BitMode, op: x86.Op, reg: mil.Register, rm: VirtRm)
	MulRegRm(reg: mil.Register, rm: VirtRm)
	DivMul(op: x86.DivMulOp, rm: VirtRm)
	Mov(mode: x86.BitMode, dst: mil.Register, src: mil.Register)
	MovImm(dst: mil.Register, value: int)
	Lea(reg: mil.Register, rm: VirtRm)
	ShiftRmReg(op: x86.ShiftOp, rm: VirtRm, amount: mil.Register)
	Push(reg: mil.Register)
	Pop(reg: mil.Register)
	CallRm(rm: VirtRm)
	Movsx8(mode: x86.BitMode, reg: mil.Register, rm: VirtRm)
	Movsx16(mode: x86.BitMode, reg: mil.Register, rm: VirtRm)
	Movzx8(mode: x86.BitMode, reg: mil.Register, rm: VirtRm)
	Movzx16(mode: x86.BitMode, reg: mil.Register, rm: VirtRm)
	CvtSi2Sx(mode: x86.SseMode, reg: mil.Register, rm: VirtRm)
	CvtSx2Si(truncate: bool, mode: x86.SseMode, reg: mil.Register, rm: VirtRm)
	CvtSs2Sd(reg: mil.Register, rm: VirtRm)
	CvtSd2Ss(reg: mil.Register, rm: VirtRm)
	Ucomisd(reg: mil.Register, rm: VirtRm)
	SseMov(mode: x86.SseMode, dst: mil.Register, src: mil.Register)
	SseOpRegRm(mode: x86.SseMode, op: x86.SseOp, reg: mil.Register, rm: VirtRm)
	SseMovRegRm(mode: x86.SseMode, reg: mil.Register, rm: VirtRm)
	SseMovRmReg(mode: x86.SseMode, rm: VirtRm, reg: mil.Register)
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
		RmReg(mode, op, rm, reg):
			"{x86.op_to_str(op)} {vrm_to_str(rm)}, {mil.vr_to_str(reg)}"
		RegRm(mode, op, reg, rm):
			"{x86.op_to_str(op)} {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		MulRegRm(reg, rm):
			"imul {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		DivMul(op, rm):
			"{x86.div_mul_op_to_str(op)} {vrm_to_str(rm)}"
		Mov(mode, dst, src):
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
		Movsx8(mode, reg, rm):
			"movsx8 {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		Movsx16(mode, reg, rm):
			"movsx16 {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		Movzx8(mode, reg, rm):
			"movzx8 {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		Movzx16(mode, reg, rm):
			"movzx16 {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		SseMov(mode, dst, src):
			"sse mov {mil.vr_to_str(dst)}, {mil.vr_to_str(src)}"
		SseOpRegRm(mode, op, reg, rm):
			"sse xx {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		CvtSi2Sx(mode, reg, rm):
			"cvtsi2{x86.sse_mode_to_str(mode)} {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		CvtSx2Si(truncate, mode, reg, rm):
			let t = "t" if truncate else ""
			"cvt{t}{x86.sse_mode_to_str(mode)}2si {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		CvtSs2Sd(reg, rm):
			"cvtss2sd {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		CvtSd2Ss(reg, rm):
			"cvtsd2ss {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		Ucomisd(reg, rm):
			"ucomisd {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		SseMovRegRm(mode, reg, rm):
			"mov{x86.sse_mode_to_str(mode)} {mil.vr_to_str(reg)}, {vrm_to_str(rm)}"
		SseMovRmReg(mode, rm, reg):
			"mov{x86.sse_mode_to_str(mode)} {vrm_to_str(rm)}, {mil.vr_to_str(reg)}"
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


fn enter_function(ctx: X86Ctx, context: SelectionContext[VirtInst], function: sil.Function):
	var index_i64 = 0
	var index_f64 = 0

	let entry_ins = context.emit_and_get(VirtInst.Entry())
	var offset = 0x10
	for p in function.parameters:
		let reg = context.get_value_vreg(p)
		if reg.kind == 0:
			if index_i64 < ctx.parameter_regs_i64.len():
				let nr = ctx.parameter_regs_i64.get(index: index_i64)
				index_i64 += 1
				reg.color = nr
				entry_ins.add_def(reg)
			else:
				# Load parameter from memory relative to RBP
				let rm = VirtRm.StackSlot(offset)
				let load_ins = context.emit_and_get(VirtInst.RegRm(mode: x86.BitMode.R64(), op: x86.Op.Mov(), reg, rm))
				load_ins.add_def(reg)
				offset += 8 # TODO: not all values are size 8.
		elif reg.kind == 1:
			if index_f64 < ctx.parameter_regs_f64.len():
				let nr = ctx.parameter_regs_f64.get(index: index_f64)
				index_f64 += 1
				reg.color = nr
				entry_ins.add_def(reg)
			else:
				panic("Floating point arguments via stack not supported.")
		else:
			panic("Unsupported parameter register class")

fn gen_prologue(frame: Frame, out: BinaryOutput):
	emit(x86.Instruction.Push(reg: rbp), out)
	emit(x86.Instruction.OpRegRm(mode: x86.BitMode.R64(), op: x86.Op.Mov(), reg: rbp, rm: x86.Rm.Reg(reg: rsp)), out)
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
	let remainder = (value + taken) % 16
	if remainder > 0:
		value + 16 - remainder
	else:
		value

fn select_instruction(ctx: X86Ctx, context: SelectionContext[VirtInst], instruction: sil.Instruction):
	""" Select machine instruction based on sil operator """
	case instruction.op:
		Const(dst, value):
			let dst_reg = context.get_value_vreg(dst)
			if dst_reg.kind == 0:
				let mov_ins = context.emit_and_get(VirtInst.MovImm(reg: dst_reg, imm: value))
				mov_ins.add_def(dst_reg)
			else:
				panic("Const not implemented for register class: {dst_reg.kind}")
		Binop(dst, op2, lhs, rhs):
			let dst_reg = context.get_value_vreg(dst)
			let lhs_reg = context.get_value_vreg(lhs)
			let rhs_reg = context.get_value_vreg(rhs)

			if dst_reg.kind == 0:
				let mode = get_int_mode(dst.ty)
				case op2:
					Add:
						move(context, mode, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(mode, op: x86.Op.Add(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Sub:
						move(context, mode, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(mode, op: x86.Op.Sub(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Mul:
						move(context, mode, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.MulRegRm(reg: dst_reg, rm: VirtRm.Reg(reg: rhs_reg)))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Div:
						let rax_reg = context.get_pre_colored(color: rax, kind: 0)
						let rdx_reg = context.get_pre_colored(color: rdx, kind: 0)
						move(context, mode, dst: rax_reg, src: lhs_reg)
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
						move(context, mode, dst: dst_reg, src: rax_reg)
					Mod:
						let rax_reg = context.get_pre_colored(color: rax, kind: 0)
						let rdx_reg = context.get_pre_colored(color: rdx, kind: 0)
						move(context, mode, dst: rax_reg, src: lhs_reg)
						let cqo_ins = context.emit_and_get(VirtInst.Actual(x86.Instruction.Cqo()))
						cqo_ins.add_use(rax_reg)
						cqo_ins.add_def(rdx_reg)
						cqo_ins.add_def(rax_reg)
						let op_ins = context.emit_and_get(VirtInst.DivMul(op: x86.DivMulOp.IDiv(), rm: VirtRm.Reg(reg: rhs_reg)))
						op_ins.add_use(rdx_reg)
						op_ins.add_use(rax_reg)
						op_ins.add_use(rhs_reg)
						op_ins.add_def(rdx_reg)
						op_ins.add_clobber(rax_reg)
						move(context, mode, dst: dst_reg, src: rdx_reg)
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
					Mod:
						panic("Cannot modulo floating point")
				let mode = get_float_mode(dst.ty)
				sse_move(context, mode, dst: dst_reg, src: lhs_reg)
				let op_ins = context.emit_and_get(VirtInst.SseOpRegRm(mode, op: sse_op, reg3: dst_reg, rm: VirtRm.Reg(reg: rhs_reg)))
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
				let mode = get_int_mode(dst.ty)
				case op:
					And:
						move(context, mode, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(mode, op: x86.Op.And(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Or:
						move(context, mode, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(mode, op: x86.Op.Or(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Xor:
						move(context, mode, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.RmReg(mode, op: x86.Op.Xor(), rm: VirtRm.Reg(reg: dst_reg), reg3: rhs_reg))
						op_ins.add_def(dst_reg)
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
					Shl:
						let rcx_reg = context.get_pre_colored(color: rcx, kind: 0)
						move(context, mode, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.ShiftRmReg(op: x86.ShiftOp.Shl(), rm: VirtRm.Reg(dst_reg), reg: rhs_reg))
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
						op_ins.add_clobber(rcx_reg)
						op_ins.add_def(dst_reg)
					Shr:
						let rcx_reg = context.get_pre_colored(color: rcx, kind: 0)
						move(context, mode, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.ShiftRmReg(op: x86.ShiftOp.Shr(), rm: VirtRm.Reg(dst_reg), reg: rhs_reg))
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
						op_ins.add_clobber(rcx_reg)
						op_ins.add_def(dst_reg)
					Sar:
						let rcx_reg = context.get_pre_colored(color: rcx, kind: 0)
						move(context, mode, dst: dst_reg, src: lhs_reg)
						let op_ins = context.emit_and_get(VirtInst.ShiftRmReg(op: x86.ShiftOp.Sar(), rm: VirtRm.Reg(dst_reg), reg: rhs_reg))
						op_ins.add_use(dst_reg)
						op_ins.add_use(rhs_reg)
						op_ins.add_clobber(rcx_reg)
						op_ins.add_def(dst_reg)
			else:
				unimplemented("bit-op on non-integer register class")
		Call(dst, callee, arguments):
			# Move arguments in proper locations:
			var p_index_i64 = 0
			var p_index_f64 = 0
			let p_regs: List[mil.Register] = List()

			let mem_args: List[mil.Register] = List()

			for arg in arguments:
				let a_reg = context.get_value_vreg(arg)
				if a_reg.kind == 0:
					let mode = get_int_mode(arg.ty)
					if p_index_i64 < ctx.parameter_regs_i64.len():
						let nr = ctx.parameter_regs_i64.get(index: p_index_i64)
						p_index_i64 += 1
						let p_reg = context.get_pre_colored(color: nr, kind: a_reg.kind)
						move(context, mode, dst: p_reg, src: a_reg)
						p_regs.append(p_reg)
					else:
						mem_args.append(a_reg)
				elif a_reg.kind == 1:
					let mode = get_float_mode(arg.ty)
					if p_index_f64 < ctx.parameter_regs_f64.len():
						let nr = ctx.parameter_regs_f64.get(index: p_index_f64)
						p_index_f64 += 1
						let p_reg = context.get_pre_colored(color: nr, kind: a_reg.kind)
						sse_move(context, mode, dst: p_reg, src: a_reg)
						p_regs.append(p_reg)
					else:
						panic("Unsupported: float registers via stack")
				else:
					panic("Unknown register class")
			var used_stack_size = mem_args.len() * 8
			let mis_align = used_stack_size % 16
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
			for clobber_reg_nr in ctx.clobber_regs:
				call_ins.add_clobber(context.get_pre_colored(color: clobber_reg_nr, kind: 0))
			# we also clobber xmm0 .. xmm15
			var reg_nr = 0
			while reg_nr < 16:
				call_ins.add_clobber(context.get_pre_colored(color: reg_nr, kind: 1))
				reg_nr += 1
			case dst:
				Some(dst_value):
					let ret_reg = context.get_value_vreg(dst_value)
					if ret_reg.kind == 0:  # i64
						let mode = get_int_mode(dst_value.ty)
						let convention_reg = context.get_pre_colored(color: rax, kind: 0)
						call_ins.add_def(convention_reg)
						move(context, mode, dst: ret_reg, src: convention_reg)
					elif ret_reg.kind == 1: # f64
						let mode = get_float_mode(dst_value.ty)
						let convention_reg = context.get_pre_colored(color: xmm0, kind: 1)
						call_ins.add_def(convention_reg)
						sse_move(context, mode, dst: ret_reg, src: convention_reg)
					else:
						panic("Invalid return register class: {ret_reg.kind}")
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
				let mov_ins = context.emit_and_get(VirtInst.RegRm(mode: get_int_mode(dst.ty), op: x86.Op.Mov(), reg, rm))
				mov_ins.add_def(reg)
				add_rm_uses(mov_ins, rm)
			elif reg.kind == 1:
				let mov_ins = context.emit_and_get(VirtInst.SseMovRegRm(mode: get_float_mode(dst.ty), reg, rm))
				mov_ins.add_def(reg)
				add_rm_uses(mov_ins, rm)
			else:
				panic("Load: Unknown register class")
		Store(address, value):
			let rm = load_addr(context, address)
			let reg = context.get_value_vreg(value)
			if reg.kind == 0:
				let mov_ins = context.emit_and_get(VirtInst.RmReg(mode: get_int_mode(value.ty), op: x86.Op.Mov(), rm, reg))
				mov_ins.add_use(reg)
				add_rm_uses(mov_ins, rm)
			elif reg.kind == 1:
				let mov_ins = context.emit_and_get(VirtInst.SseMovRmReg(mode: get_float_mode(value.ty), rm, reg))
				mov_ins.add_use(reg)
				add_rm_uses(mov_ins, rm)
			else:
				panic("Store: Unknown register class")
		Convert(signed, dst, value):
			let dst_reg = context.get_value_vreg(dst)
			let value_reg = context.get_value_vreg(value)
			case dst.ty:
				F64:
					case value.ty:
						F64:
							unimplemented("Convert f64 to f64")
						F32:
							let rm = VirtRm.Reg(value_reg)
							let conv_ins = context.emit_and_get(VirtInst.CvtSs2Sd(reg: dst_reg, rm))
							conv_ins.add_def(dst_reg)
							conv_ins.add_use(value_reg)
						I64:
							let rm = VirtRm.Reg(value_reg)
							let conv_ins = context.emit_and_get(VirtInst.CvtSi2Sx(mode: x86.SseMode.Double(), reg: dst_reg, rm))
							conv_ins.add_def(dst_reg)
							conv_ins.add_use(value_reg)
						I32:
							unimplemented("Convert i32 to f64")
						I16:
							unimplemented("Convert i16 to f64")
						I8:
							unimplemented("Convert i8 to f64")
				F32:
					case value.ty:
						F64:
							let rm = VirtRm.Reg(value_reg)
							let conv_ins = context.emit_and_get(VirtInst.CvtSd2Ss(reg: dst_reg, rm))
							conv_ins.add_def(dst_reg)
							conv_ins.add_use(value_reg)
						F32:
							unimplemented("Convert f32 to f32")
						I64:
							unimplemented("Convert i64 to f32")
						I32:
							unimplemented("Convert i32 to f32")
						I16:
							unimplemented("Convert i16 to f32")
						I8:
							unimplemented("Convert i8 to f32")
				I64:
					case value.ty:
						F64:
							let rm = VirtRm.Reg(value_reg)
							let conv_ins = context.emit_and_get(VirtInst.CvtSx2Si(truncate: true, mode: x86.SseMode.Double(), reg: dst_reg, rm))
							conv_ins.add_def(dst_reg)
							conv_ins.add_use(value_reg)
						F32:
							let rm = VirtRm.Reg(value_reg)
							let conv_ins = context.emit_and_get(VirtInst.CvtSx2Si(truncate: true, mode: x86.SseMode.Single(), reg: dst_reg, rm))
							conv_ins.add_def(dst_reg)
							conv_ins.add_use(value_reg)
						I64:
							move(context, mode: x86.BitMode.R64(), dst: dst_reg, src: value_reg)
						I32:
							# TODO: Sign extend, use CDQE?
							unimplemented("Convert i32 to i64")
						I16:
							let rm = VirtRm.Reg(value_reg)
							let mode = x86.BitMode.R64()
							let vi = if signed:
								VirtInst.Movsx16(mode, reg: dst_reg, rm)
							else:
								VirtInst.Movzx16(mode, reg: dst_reg, rm)
							let sx_ins = context.emit_and_get(vi)
							sx_ins.add_def(dst_reg)
							sx_ins.add_use(value_reg)
						I8:
							let rm = VirtRm.Reg(value_reg)
							let mode = x86.BitMode.R64()
							let vi = if signed:
								VirtInst.Movsx8(mode, reg: dst_reg, rm)
							else:
								VirtInst.Movzx8(mode, reg: dst_reg, rm)
							let sx_ins = context.emit_and_get(vi)
							sx_ins.add_def(dst_reg)
							sx_ins.add_use(value_reg)
				I32:
					case value.ty:
						F64:
							unimplemented("Convert to f64 to i32")
						F32:
							unimplemented("Convert to f32 to i32")
						I64:
							move(context, mode: x86.BitMode.R32(), dst: dst_reg, src: value_reg)
						I32:
							move(context, mode: x86.BitMode.R32(), dst: dst_reg, src: value_reg)
						I16:
							let rm = VirtRm.Reg(value_reg)
							let mode = x86.BitMode.R32()
							let vi = if signed:
								VirtInst.Movsx16(mode, reg: dst_reg, rm)
							else:
								VirtInst.Movzx16(mode, reg: dst_reg, rm)
							let sx_ins = context.emit_and_get(vi)
							sx_ins.add_def(dst_reg)
							sx_ins.add_use(value_reg)
						I8:
							let rm = VirtRm.Reg(value_reg)
							let mode = x86.BitMode.R32()
							let vi = if signed:
								VirtInst.Movsx8(mode, reg: dst_reg, rm)
							else:
								VirtInst.Movzx8(mode, reg: dst_reg, rm)
							let sx_ins = context.emit_and_get(vi)
							sx_ins.add_def(dst_reg)
							sx_ins.add_use(value_reg)
				I16:
					case value.ty:
						F64:
							unimplemented("Convert to f64 to i16")
						F32:
							unimplemented("Convert to f32 to i16")
						I64:
							move(context, mode: x86.BitMode.R16(), dst: dst_reg, src: value_reg)
						I32:
							move(context, mode: x86.BitMode.R16(), dst: dst_reg, src: value_reg)
						I16:
							move(context, mode: x86.BitMode.R16(), dst: dst_reg, src: value_reg)
						I8:
							# TODO: Sign extend
							unimplemented("Convert to i8 to i16")
				I8:
					case value.ty:
						F64:
							unimplemented("Convert to f64 to i8")
						F32:
							unimplemented("Convert to f32 to i8")
						I64:
							move(context, mode: x86.BitMode.R8(), dst: dst_reg, src: value_reg)
						I32:
							move(context, mode: x86.BitMode.R8(), dst: dst_reg, src: value_reg)
						I16:
							move(context, mode: x86.BitMode.R8(), dst: dst_reg, src: value_reg)
						I8:
							move(context, mode: x86.BitMode.R8(), dst: dst_reg, src: value_reg)

		Jump(label):
			context.emit(VirtInst.Actual(instruction: x86.Instruction.Jmp(label)))
		JumpIf(lhs, condition, rhs, label1, label2):
			let lhs_reg = context.get_value_vreg(lhs)
			let rhs_reg = context.get_value_vreg(rhs)
			if lhs_reg.kind == 0:
				let rm3 = VirtRm.Reg(reg: lhs_reg)
				let cmp_ins = context.emit_and_get(VirtInst.RmReg(mode: x86.BitMode.R64(), op: x86.Op.Cmp(), rm3, reg3: rhs_reg))
				cmp_ins.add_use(lhs_reg)
				cmp_ins.add_use(rhs_reg)
				let cmp_op = case condition:
					Eq: x86.Cond.Jz()
					Neq: x86.Cond.Jnz()
					Gt: x86.Cond.Jg()
					Lt: x86.Cond.Jl()
					Gte: x86.Cond.Jge()
					Lte: x86.Cond.Jle()
				context.emit(VirtInst.Actual(instruction: x86.Instruction.Jcc(cmp_op, label1)))
			elif lhs_reg.kind == 1:
				let cmp_ins = context.emit_and_get(VirtInst.Ucomisd(reg: lhs_reg, rm3: VirtRm.Reg(reg: rhs_reg)))
				cmp_ins.add_use(lhs_reg)
				cmp_ins.add_use(rhs_reg)
				let cmp_op = case condition:
					Eq: x86.Cond.Jz()
					Neq: x86.Cond.Jnz()
					Gt: x86.Cond.Ja()
					Lt: x86.Cond.Jb()
					Gte: x86.Cond.Jae()
					Lte: x86.Cond.Jbe()
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

fn get_int_mode(ty?: sil.Type) -> x86.BitMode:
	case ty:
		F64: panic("Invalid integer type f64")
		F32: panic("Invalid integer type f32")
		I64: x86.BitMode.R64()
		I32: x86.BitMode.R32()
		I16: x86.BitMode.R16()
		I8: x86.BitMode.R8()

fn get_float_mode(ty?: sil.Type) -> x86.SseMode:
	case ty:
		F64: x86.SseMode.Double()
		F32: x86.SseMode.Single()
		I64: panic("Invalid float type i64")
		I32: panic("Invalid float type i32")
		I16: panic("Invalid float type i16")
		I8: panic("Invalid float type i8")

fn add_rm_uses(minst?: mil.Instruction[VirtInst], rm: VirtRm):
	""" Add use information for RM mode """
	case rm:
		RegDisp(reg, offset):
			minst.add_use(reg)
	else:
		pass

fn move(context: SelectionContext[VirtInst], mode: x86.BitMode, dst: mil.Register, src: mil.Register):
	let mov_ins = context.emit_and_get(VirtInst.Mov(mode, dst, src))
	mov_ins.add_def(dst)
	mov_ins.add_use(src)
	mov_ins.is_move = true

fn sse_move(context: SelectionContext[VirtInst], mode: x86.SseMode, dst: mil.Register, src: mil.Register):
	let mov_ins = context.emit_and_get(VirtInst.SseMov(mode, dst, src))
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
				let instruction = x86.Instruction.OpRegRm(mode: x86.BitMode.R64(), op: x86.Op.Xor(), reg: reg2, rm: x86.Rm.Reg(reg2))
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
		RegRm(mode, op, reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			let instruction = x86.Instruction.OpRegRm(mode, op, reg: reg2, rm: rm2)
			emit(instruction, out)
		RmReg(mode, op, rm, reg):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			let instruction = x86.Instruction.OpRmReg(mode, op, rm: rm2, reg: reg2)
			emit(instruction, out)
		MulRegRm(reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			let instruction = x86.Instruction.MulRegRm(reg: reg2, rm: rm2)
			emit(instruction, out)
		DivMul(op, rm):
			let rhs_rm = mat_rm(rm)
			emit(x86.Instruction.DivMul(op, rm: rhs_rm), out)
		Mov(mode, dst, src):
			if dst.color != src.color:
				let dst_reg = mat_reg(reg: dst)
				let rm = x86.Rm.Reg(reg: mat_reg(reg: src))
				if dst.kind == 0:
					emit(x86.Instruction.OpRegRm(mode, op: x86.Op.Mov(), reg: dst_reg, rm), out)
				else:
					panic("Move not supported for register class {dst.kind}")
		ShiftRmReg(op, rm, reg):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.OpRegRm(mode: x86.BitMode.R64(), op: x86.Op.Mov(), reg: rcx, rm: x86.Rm.Reg(reg2)), out)
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
		Movsx8(mode, reg, rm):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.Movsx8(mode, reg: reg2, rm: rm2), out)
		Movsx16(mode, reg, rm):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.Movsx16(mode, reg: reg2, rm: rm2), out)
		Movzx8(mode, reg, rm):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.Movzx8(mode, reg: reg2, rm: rm2), out)
		Movzx16(mode, reg, rm):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.Movzx16(mode, reg: reg2, rm: rm2), out)
		SseMov(mode, dst, src):
			if dst.color != src.color:
				let dst_reg = mat_reg(reg: dst)
				let rm = x86.Rm.Reg(reg: mat_reg(reg: src))
				if dst.kind == 1:
					emit(x86.Instruction.SseMovRegRm(mode, reg: dst_reg, rm), out)
				else:
					panic("SseMove not supported for register class {dst.kind}")
		SseOpRegRm(mode, op, reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.SseOpRegRm(mode, op, reg: reg2, rm: rm2), out)
		CvtSi2Sx(mode, reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.CvtSi2Sx(mode, reg: reg2, rm: rm2), out)
		CvtSx2Si(truncate, mode, reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.CvtSx2Si(truncate, mode, reg: reg2, rm: rm2), out)
		CvtSs2Sd(reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.CvtSs2Sd(reg: reg2, rm: rm2), out)
		CvtSd2Ss(reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.CvtSd2Ss(reg: reg2, rm: rm2), out)
		Ucomisd(reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.Ucomisd(reg: reg2, rm: rm2), out)
		SseMovRegRm(mode, reg, rm):
			let reg2 = mat_reg(reg)
			let rm2 = mat_rm(rm)
			emit(x86.Instruction.SseMovRegRm(mode, reg: reg2, rm: rm2), out)
		SseMovRmReg(mode, rm, reg):
			let rm2 = mat_rm(rm)
			let reg2 = mat_reg(reg)
			emit(x86.Instruction.SseMovRmReg(mode, rm: rm2, reg: reg2), out)
		Exit:
			if minst.uses.len() > 0:
				let src = minst.uses.get(index: 0)
				let rm = x86.Rm.Reg(reg: mat_reg(reg: src))
				emit(x86.Instruction.OpRegRm(mode: x86.BitMode.R64(), op: x86.Op.Mov(), reg: rax, rm), out)
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
