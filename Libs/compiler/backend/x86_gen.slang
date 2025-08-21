
# x86 backend

from utils import log_info
import sil
import mil
import x86
from codegen import cgen, SelectionContext, Backend

pub fn gen_x86(program: sil.Program):
	log_info("Generating x86 instructions")
	let backend: Backend[x86.Instruction] = Backend:
		selector: select_instruction
		materializer: materialize
		instruction_as_str: x86.instruction_to_string
		to_binstream: x86.emit_instruction
	cgen(program, backend)


fn select_instruction(context: SelectionContext[x86.Instruction], instruction: sil.Instruction):
	""" Select machine instruction based on sil operator """
	case instruction.op:
		Binop(dst, op2, lhs, rhs):
			case op2:
				Add:
					pass
			else:
				pass
		Call(dst, callee, arguments):
			context.emit(x86.Instruction.Call())
		Load(dst, addr):
			let x = context.emit_and_get(x86.Instruction.MovRegRm(reg: 0, rm: 0))
			let r1 = context.new_vreg(kind: 0)
			let r2 = context.new_vreg(kind: 0)
			x.add_def(r: r1)
			x.add_use(r: r2)
		Store(addr, value):
			context.emit(x86.Instruction.MovRmReg(rm: 0, reg: 0))
	else:
		pass

fn materialize(x: mil.Instruction[x86.Instruction]) -> x86.Instruction:
	case x.instruction:
		MovRegRm(reg, rm):
			let reg2 = x.defs.get(index: 0).color
			let reg3 = x.uses.get(index: 0).color
			x86.Instruction.MovRegRm(reg: reg2, rm: reg3)
	else:
		x.instruction
