""" Generate riscv code

 Register usage convention:    (saver)
 x0 -> zero -> hardwired 0
 x1 -> ra   -> return address  (caller)
 x2 -> sp   -> stack pointer   (caller)
 x3 -> gp   -> global pointer
 x4 -> tp   -> thread pointer
 x5-x7      -> temporaries     (caller)
 x8
 x9
 x18-x27 -> s2-11 -> saved registers (callee)
 x28-31 -> t3-6 -> temporaries (caller)

 Pseudo instructions:
 NOP  > ADDI x0, x0, 0
 RET  > JALR x0, 0(ra)
 J offset  > JAL x0, offset
 MV rd, rs  > ADDI rd, rs, 0
"""

import sil
import mil
import riscv
from bytes import ByteArray
from optiontype import Option
from listtype import List, list4, list8
from codegen import cgen, CodegenOptions
from isel import Backend, SelectionContext, Frame
from outstream import BinaryOutput, DataItem
from report import Report
from utils import unimplemented, panic
from logging import log_info

pub fn gen_riscv(program: sil.Program, options: CodegenOptions):
	log_info("Generating riscv code")
	let all_regs: List[int] = list4(18, 19, 20, 21)
	let all_regs2: List[int] = list4(18, 19, 20, 21)
	let backend: Backend[VirtInst] = Backend:
		bits: 32
		all_regs
		all_regs2
		enter: enter_function
		selector: select_instruction
		to_str: vinst_to_str
		materializer: materialize
		emit_prologue: gen_prologue
		emit_epilogue: gen_epilogue
		fixer: riscv.apply_reloc
		is_pic_reloc: riscv.is_pic_reloc
		emit_data: gen_data_item

	cgen(program, backend, options)

enum VirtInst:
	Jal
	Exit
	Branch(cond: riscv.Cond, rs1: mil.Register, rs2: mil.Register, label: str)
	Mov(dst: mil.Register, src: mil.Register)
	LoadImmediate(dst: mil.Register, value: int)
	LoadAddress(dst: mil.Register, name: str)
	RegRegImm(op: riscv.ImmOp, dst: mil.Register, src: mil.Register, imm: int)
	RegRegReg(op: riscv.RegOp, dst: mil.Register, src1: mil.Register, src2: mil.Register)
	Load(op: riscv.LoadOp, reg: mil.Register, addr: Address)
	Store(op: riscv.StoreOp, reg: mil.Register, addr: Address)
	Actual(instruction: riscv.Instruction)

struct Address:
	reg: mil.Register
	offset: int

fn vinst_to_str(vi: VirtInst) -> str:
	case vi:
		Jal: "virt-ins"
		Exit: "exit"
		Branch(cond, rs1, rs2, label): "b{riscv.cond_to_string(cond)} {mil.vr_to_str(rs1)}, {mil.vr_to_str(rs2)} {label}"
		Mov(dst, src): "mv {mil.vr_to_str(dst)},{mil.vr_to_str(src)}"
		LoadImmediate(dst, value): "li {mil.vr_to_str(dst)}, {value}"
		LoadAddress(dst, name): "la {mil.vr_to_str(dst)}, {name}"
		RegRegImm(op, dst, src, imm): "{riscv.imm_op_to_string(op)} {mil.vr_to_str(dst)}, {mil.vr_to_str(src)}, {imm}"
		RegRegReg(op, dst, src1, src2): "{riscv.reg_op_to_string(op)} {mil.vr_to_str(dst)}, {mil.vr_to_str(src1)}, {mil.vr_to_str(src2)}"
		Load(op, reg, addr): "{riscv.load_op_to_string(op)} {mil.vr_to_str(reg)}, {addr_to_str(addr)}"
		Store(op, reg, addr): "{riscv.store_op_to_string(op)} {mil.vr_to_str(reg)}, {addr_to_str(addr)}"
		Actual(instruction): riscv.instruction_to_string(instruction)

fn addr_to_str(addr: Address) -> str:
	"{addr.offset}({mil.vr_to_str(reg: addr.reg)})"

fn enter_function(context: SelectionContext[VirtInst], function: sil.Function):
	pass

fn select_instruction(context: SelectionContext[VirtInst], instruction: sil.Instruction):
	""" Select machine instruction based on sil operator """
	case instruction.op:
		Const(dst, value):
			let dst_reg = context.get_value_vreg(dst)
			let load_ins = context.emit_and_get(VirtInst.LoadImmediate(dst_reg, value))
			load_ins.add_def(dst_reg)
		Jump(label):
			context.emit(VirtInst.Actual(riscv.Instruction.J(label)))
		JumpIf(lhs, condition, rhs, label1, label2):
			let src1_reg = context.get_value_vreg(lhs)
			let src2_reg = context.get_value_vreg(rhs)
			let cond = case condition:
				Eq: riscv.Cond.EQ()
				Neq: riscv.Cond.NE()
				Gt: riscv.Cond.LT()
				Lt: riscv.Cond.LT()
				Gte: riscv.Cond.GE()
				Lte: riscv.Cond.GE()
			let do_swap = case condition:
				Gt: true
				Lte: true
			else:
				false
			let b_ins = if do_swap:
				context.emit_and_get(VirtInst.Branch(cond, rs1: src2_reg, rs2: src1_reg, label1))
			else:
				context.emit_and_get(VirtInst.Branch(cond, rs1: src1_reg, rs2: src2_reg, label1))
			b_ins.add_use(src1_reg)
			b_ins.add_use(src2_reg)
			context.emit(VirtInst.Actual(riscv.Instruction.J(label2)))
		Binop(dst, op2, lhs, rhs):
			let dst_reg = context.get_value_vreg(dst)
			let src1_reg = context.get_value_vreg(lhs)
			let src2_reg = context.get_value_vreg(rhs)
			case op2:
				Add:
					emit_regregreg(context, op: riscv.RegOp.ADD(), dst_reg, src1_reg, src2_reg)
				Sub:
					emit_regregreg(context, op: riscv.RegOp.SUB(), dst_reg, src1_reg, src2_reg)
				Div:
					unimplemented("Divide")
				Mod:
					unimplemented("Modulo")
				Mul:
					unimplemented("Multiply")
		Bitop(dst, op, lhs, rhs):
			let dst_reg = context.get_value_vreg(dst)
			let src1_reg = context.get_value_vreg(lhs)
			let src2_reg = context.get_value_vreg(rhs)
			case op:
				Shr:
					emit_regregreg(context, op: riscv.RegOp.SRL(), dst_reg, src1_reg, src2_reg)
				Sar:
					emit_regregreg(context, op: riscv.RegOp.SRA(), dst_reg, src1_reg, src2_reg)
				Shl:
					emit_regregreg(context, op: riscv.RegOp.SLL(), dst_reg, src1_reg, src2_reg)
				Xor:
					emit_regregreg(context, op: riscv.RegOp.XOR(), dst_reg, src1_reg, src2_reg)
				And:
					emit_regregreg(context, op: riscv.RegOp.AND(), dst_reg, src1_reg, src2_reg)
				Or:
					emit_regregreg(context, op: riscv.RegOp.OR(), dst_reg, src1_reg, src2_reg)
		GetAddress(dst, address):
			let dst_reg = context.get_value_vreg(dst)
			case address:
				Global(name):
					let load_ins = context.emit_and_get(VirtInst.LoadAddress(dst_reg, name))
					load_ins.add_def(dst_reg)
				StackSlot(offset):
					unimplemented("GetAddress / stack slot")
				Ptr(base):
					let p_reg = context.get_value_vreg(base)
					emit_move(context, dst: dst_reg, src: p_reg)
		Convert(signed, dst, value):
			unimplemented("Convert")
		Call(dst, callee, arguments):
			# Setup arguments
			let parameter_regs_i: List[int] = list8(10, 11, 12, 13, 14, 15, 16, 17) # a0 .. a7
			var index_i = 0
			for argument in arguments:
				let a_reg = context.get_value_vreg(argument)
				if index_i < parameter_regs_i.len():
					let nr = parameter_regs_i.get(index: index_i)
					index_i += 1
					let p_reg = context.get_pre_colored(color: nr, kind: a_reg.kind)
					emit_move(context, dst: p_reg, src: a_reg)
				else:
					panic("Unsupported: more than 8 arguments")

			# Invoke function
			case callee:
				Global(name):
					context.emit(VirtInst.Actual(riscv.Instruction.CALL(name)))
			else:
				unimplemented("Call: {sil.address_to_string(callee)}")

			# Eventually gather return value
			case dst:
				Some(value):
					let ret_reg = context.get_value_vreg(value)
					let a0_reg = context.get_pre_colored(color: 10, kind: ret_reg.kind)
					emit_move(context, dst: ret_reg, src: a0_reg)
				None:
					pass
		Return(v):
			context.emit(VirtInst.Exit())
		Halt:
			context.emit(VirtInst.Actual(i: riscv.Instruction.EBREAK()))
		Load(dst, addr):
			let dst_reg = context.get_value_vreg(dst)
			let addr2 = load_addr(context, addr)
			let op = case dst.ty:
				F64:
					panic("Store f64 not supported")
				F32:
					panic("Store f32 not supported")
				I64:
					# panic("Store i64 not supported")
					riscv.LoadOp.LW()
				I32:
					riscv.LoadOp.LW()
				I16:
					riscv.LoadOp.LH()
				I8:
					riscv.LoadOp.LB()
			let offset = 0
			let load_ins = context.emit_and_get(VirtInst.Load(op, dst_reg, addr: addr2))
			# TODO: add usage of addr2
			load_ins.add_def(dst_reg)
		Store(addr, value):
			let value_reg = context.get_value_vreg(value)
			let addr2 = load_addr(context, addr)
			let op = case value.ty:
				F64:
					panic("Store f64 not supported")
				F32:
					panic("Store f32 not supported")
				I64:
					# panic("Store i64 not supported")
					riscv.StoreOp.SW()
				I32:
					riscv.StoreOp.SW()
				I16:
					riscv.StoreOp.SH()
				I8:
					riscv.StoreOp.SB()
			let store_ins = context.emit_and_get(VirtInst.Store(op, value_reg, addr: addr2))
			# TODO: add usage of addr2
			store_ins.add_use(value_reg)

	# fn gen_literal(literal: bc.LiteralValue):
	#     case literal:
	#         Int(value):
	#             reg += 1
	#             emit(riscv.Instruction.ADDI(rd: reg, rs1: 0, imm: value))
	#         Float(value):
	#             panic("TODO: Float")
	#         Str(value):
	#             panic("TODO: Str")
	#         Bool(value):
	#             let imm = 0
	#             if value:
	#                 imm = 1
	#             reg += 1
	#             emit(riscv.Instruction.ADDI(rd: reg, rs1: 0, imm))
	#         Char(value):
	#             let imm = ord(value)
	#             reg += 1
	#             emit(riscv.Instruction.ADDI(rd: reg, rs1: 0, imm))
	#         Null:
	#             panic("TODO: Null")

fn load_addr(context: SelectionContext[VirtInst], addr: sil.Address) -> Address:
	case addr:
		Global(name):
			unimplemented("load_addr / name")
		StackSlot(offset):
			let sp_reg = context.get_pre_colored(color: 2, kind: 0)
			Address(reg: sp_reg, offset)
		Ptr(base):
			let p_reg = context.get_value_vreg(base)
			Address(reg: p_reg, offset: 0)

# fn add_addr_usages(i: )
fn emit_regregreg(context: SelectionContext[VirtInst], op: riscv.RegOp, dst_reg: mil.Register, src1_reg: mil.Register, src2_reg: mil.Register):
	let add_ins = context.emit_and_get(VirtInst.RegRegReg(op, dst_reg, src1_reg, src2_reg))
	add_ins.add_def(dst_reg)
	add_ins.add_use(src1_reg)
	add_ins.add_use(src2_reg)

fn emit_regregimm(context: SelectionContext[VirtInst], op: riscv.ImmOp, dst_reg: mil.Register, src_reg: mil.Register, imm: int):
	let const_ins = context.emit_and_get(VirtInst.RegRegImm(op, dst_reg, src_reg, imm))
	const_ins.add_def(dst_reg)
	const_ins.add_use(src_reg)

fn emit_move(context: SelectionContext[VirtInst], dst: mil.Register, src: mil.Register):
	let mov_ins = context.emit_and_get(VirtInst.Mov(dst, src))
	mov_ins.add_def(dst)
	mov_ins.add_use(src)

fn materialize(context: SelectionContext[VirtInst], v: mil.Instruction[VirtInst], outstream: BinaryOutput):
	""" Apply actual registers to instruction now. """
	case v.instruction:
		Jal:
			# rd = v.defs[0]
			let instruction = riscv.Instruction.JAL(rd: 0, imm: 0)
			riscv.do_emit(instruction, outstream)
		Exit:
			riscv.do_emit(instruction: riscv.Instruction.J(label: context.frame.exit_label), outstream)
		Branch(cond, rs1, rs2, label):
			riscv.do_emit(instruction: riscv.Instruction.Branch(cond, rs1: mat_reg(reg: rs1), rs2: mat_reg(reg: rs2), label), outstream)
		Mov(dst, src):
			riscv.do_emit(instruction: riscv.Instruction.MOV(dst: mat_reg(reg: dst), src: mat_reg(reg: src)), outstream)
		LoadAddress(dst, name):
			riscv.do_emit(instruction: riscv.Instruction.LA(rd: mat_reg(reg: dst), name), outstream)
		LoadImmediate(dst, value):
			riscv.do_emit(instruction: riscv.Instruction.LI(rd: mat_reg(reg: dst), value), outstream)
		RegRegImm(op, dst, src, imm):
			let rd = mat_reg(reg: dst)
			let rs1 = mat_reg(reg: src)
			let instruction = riscv.Instruction.RegImm(op, rd, rs1, imm)
			riscv.do_emit(instruction, outstream)
		RegRegReg(op, dst, src1, src2):
			let rd = mat_reg(reg: dst)
			let rs1 = mat_reg(reg: src1)
			let rs2 = mat_reg(reg: src2)
			let instruction = riscv.Instruction.ThreeRegsOp(op, rd, rs1, rs2)
			riscv.do_emit(instruction, outstream)
		Load(op, dst, addr):
			let rd = mat_reg(reg: dst)
			let rs1 = mat_reg(reg: addr.reg)
			let imm = addr.offset
			let instruction = riscv.Instruction.Load(op, rd, rs1, imm)
			riscv.do_emit(instruction, outstream)
		Store(op, reg, addr):
			let rs1 = mat_reg(reg: addr.reg)
			let rs2 = mat_reg(reg)
			let imm = addr.offset
			let instruction = riscv.Instruction.Store(op, rs1, rs2, imm)
			riscv.do_emit(instruction, outstream)
		Actual(instruction):
			riscv.do_emit(instruction, outstream)

fn mat_reg(reg: mil.Register) -> int:
	reg.color

fn gen_prologue(frame: Frame, outstream: BinaryOutput):
	# TODO: reserve stack space
	riscv.do_emit(instruction: riscv.Instruction.RegImm(op: riscv.ImmOp.ADDI(), rd: 2, rs1: 2, imm: -16), outstream)
	# Save ra:
	riscv.do_emit(instruction: riscv.Instruction.Store(op: riscv.StoreOp.SW(), rs1: 2, rs2: 1, imm: 12), outstream)

fn gen_epilogue(frame: Frame, outstream: BinaryOutput):
	riscv.do_emit(instruction: riscv.Instruction.Load(op: riscv.LoadOp.LW(), rd: 1, rs1: 2, imm: 12), outstream)
	riscv.do_emit(instruction: riscv.Instruction.RegImm(op: riscv.ImmOp.ADDI(), rd: 2, rs1: 2, imm: 16), outstream)
	riscv.do_emit(instruction: riscv.Instruction.RET(), outstream)

fn gen_data_item(item: DataItem, out: BinaryOutput):
	pass
