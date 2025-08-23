
# x86 backend

from utils import log_info, unimplemented
import sil
import mil
import x86
from codegen import cgen, SelectionContext, Backend

# TODO:
# type SelectionContext[x86.Instruction] Ctx

pub fn gen_x86(program: sil.Program):
	log_info("Generating x86 instructions")
	let backend: Backend[x86.Instruction] = Backend:
		selector: select_instruction
		materializer: materialize
		instruction_as_str: x86.instruction_to_string
		to_binstream: x86.emit_instruction
	cgen(program, backend)

fn fetch_value(context: SelectionContext[x86.Instruction], value: sil.Value) -> mil.Register:
	case value:
		Integer(value):
			context.emit(x86.Instruction.MovRegImm(reg: 0, imm: value))
			context.new_vreg(kind: 0)
		Global(name):
			unimplemented("global value")
		Tmp(name):
			context.new_vreg(kind: 0)

fn select_instruction(context: SelectionContext[x86.Instruction], instruction: sil.Instruction):
	""" Select machine instruction based on sil operator """
	case instruction.op:
		Alloc(addr, size):
			pass
		Binop(dst, op2, lhs, rhs):
			case op2:
				Add:
					let dst_reg = context.get_value_vreg(dst)
					let lhs_reg = fetch_value(context, value: lhs)
					let rhs_reg = fetch_value(context, value: rhs)

					let x1 = context.emit_and_get(x86.Instruction.MovRegRm(reg: 0, rm: x86.Rm.Reg(reg: 0)))
					x1.add_def(r: dst_reg)
					x1.add_use(r: lhs_reg)

					let x2 = context.emit_and_get(x86.Instruction.AddRmReg(rm: x86.Rm.Reg(reg: 0), reg: 0))
					x2.add_def(r: dst_reg)
					x2.add_use(r: dst_reg)
					x2.add_use(r: rhs_reg)
			else:
				unimplemented("select: {instruction}")
		Call(dst, callee, arguments):
			context.emit(x86.Instruction.Call())
		Load(dst, addr):
			let x = context.emit_and_get(x86.Instruction.MovRegRm(reg: 0, rm: x86.Rm.MemDisp8(reg: 0, disp: 5)))
			let dst_reg = context.get_value_vreg(dst)
			let addr_reg = context.get_value_vreg(addr)
			x.add_def(r: dst_reg)
			x.add_use(r: addr_reg)
		Store(addr, value):
			context.emit(x86.Instruction.MovRmReg(rm: x86.Rm.MemDisp8(reg: 0, disp: 9), reg: 0))
		Return(v):
			context.emit(x86.Instruction.Ret())
	else:
		unimplemented("select: {instruction}")

fn materialize(x: mil.Instruction[x86.Instruction]) -> x86.Instruction:
	case x.instruction:
		MovRegRm(reg, rm):
			let reg2 = x.defs.get(index: 0).color
			let rm3 = mat_rm(rm, color: x.uses.get(index: 0).color)
			x86.Instruction.MovRegRm(reg: reg2, rm: rm3)
	else:
		x.instruction

fn mat_rm(rm: x86.Rm, color: int) -> x86.Rm:
	""" Materialize a Rm """
	case rm:
		Mem(reg):
			x86.Rm.Mem(reg: color)
		MemDisp8(reg, disp):
			x86.Rm.MemDisp8(reg: color, disp)
		MemDisp32(reg, disp):
			x86.Rm.MemDisp32(reg: color, disp)
		Reg(reg):
			x86.Rm.Reg(reg: color)
