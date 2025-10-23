from utils import unimplemented
import sil
import mil
import x86
from codegen import SelectionContextV2


fn fetch_value_v2(context: SelectionContextV2[x86.Instruction], value: sil.Value) -> mil.Register:
	case value:
		Global(name):
			unimplemented("global value")
		Tmp(name):
			context.new_vreg(kind: 0)
		StackSlot(offset):
			unimplemented("stack value")

pub fn select_instruction_v2(context: SelectionContextV2[x86.Instruction], instruction: sil.Instruction):
	""" Select machine instruction based on sil operator """
	case instruction.op:
		Alloc(addr, size):
			pass
		Binop(dst, op2, lhs, rhs):
			case op2:
				Add:
					let dst_reg = context.get_value_vreg(dst)
					let lhs_reg = fetch_value_v2(context, value: lhs)
					let rhs_reg = fetch_value_v2(context, value: rhs)

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

pub fn materialize(x: mil.Instruction[x86.Instruction]) -> x86.Instruction:
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
