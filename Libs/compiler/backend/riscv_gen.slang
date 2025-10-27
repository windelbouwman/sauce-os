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
from listtype import List, list4
from codegen import Backend, SelectionContext, Frame, cgen
from outstream import BinaryOutput
from utils import unimplemented
from logging import log_info

pub fn gen_riscv(program: sil.Program, filename: Option[str]):
	log_info("Generating riscv code")
	program.dump()
	let all_regs: List[int] = list4(18, 19, 20, 21)
	let backend: Backend[VirtInst] = Backend:
		all_regs
		enter: enter_function
		selector: select_instruction
		to_str: vinst_to_str
		materializer: materialize
		emit_prologue: gen_prologue
		emit_epilogue: gen_epilogue

	unimplemented("TODO")
	cgen(program, backend, filename)

enum VirtInst:
	Jal
	Mov
	Add
	Sub
	Load
	Store
	X(i: riscv.Instruction)

fn vinst_to_str(vi: VirtInst) -> str:
	"virt-ins"

fn enter_function(context: SelectionContext[VirtInst], function: sil.Function):
	pass

fn select_instruction(context: SelectionContext[VirtInst], instruction: sil.Instruction):
	""" Select machine instruction based on sil operator """
	case instruction.op:
		Nop:
			pass
		Const(dst, value):
			unimplemented("Const")
		Jump(label):
			context.emit(VirtInst.Jal())
		JumpNonZero(condition, label1, label2):
			context.emit(VirtInst.Jal())
		Binop(dst, op2, lhs, rhs):
			case op2:
				Add:
					context.emit(VirtInst.Add())
				Sub:
					context.emit(VirtInst.Sub())
				Div:
					unimplemented("Divide")
				Mul:
					unimplemented("Multiply")
		Compare(dst, op2, lhs, rhs):
			unimplemented("Comparison")
		Call(dst, callee, arguments):
			# panic("TODO: Call")
			# TODO: address?

			# Setup arguments
			for argument in arguments:
				case argument:
					Tmp(name):
						context.emit(VirtInst.Mov())
					Global(name):
						context.emit(VirtInst.Load())
				else:
					unimplemented("arg: {sil.value_to_string(argument)}")

			# Invoke function
			case callee:
				Global(name):
					context.emit(VirtInst.Jal())
				Tmp(name):
					context.emit(VirtInst.Jal())
			else:
				unimplemented("Call: {sil.value_to_string(callee)}")

			# Eventually gather return value
			case dst:
				Some(value):
					pass
				None:
					pass
		Return(v):
			context.emit(VirtInst.X(i: riscv.Instruction.RET()))
		Halt:
			context.emit(VirtInst.X(i: riscv.Instruction.EBREAK()))
		Alloc(addr, size):
			pass
		Load(dst, addr):
			let offset = 0
			context.emit(VirtInst.Load())
		Store(addr, value):
			let offset = 0
			context.emit(VirtInst.Store())

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


	# fn gen_bitop(op: bc.BitOperator):
	#     reg -= 1
	#     case op:
	#         Shr:
	#             emit(riscv.Instruction.SRL(rd: reg, rs1: reg, rs2: reg + 1))
	#         Shl:
	#             emit(riscv.Instruction.SLL(rd: reg, rs1: reg, rs2: reg + 1))
	#         Xor:
	#             emit(riscv.Instruction.XOR(rd: reg, rs1: reg, rs2: reg + 1))
	#         And:
	#             emit(riscv.Instruction.AND(rd: reg, rs1: reg, rs2: reg + 1))
	#         Or:
	#             emit(riscv.Instruction.OR(rd: reg, rs1: reg, rs2: reg + 1))



fn materialize(v: mil.Instruction[VirtInst], outstream: BinaryOutput):
	""" Apply actual registers to instruction now. """
	case v.instruction:
		Jal:
			# rd = v.defs[0]
			let instruction = riscv.Instruction.JAL(rd: 0, imm: 0)
			do_emit(instruction, outstream)
	else:
		unimplemented("TODO!")

fn do_emit(instruction: riscv.Instruction, outstream: BinaryOutput):
	let code = riscv.encode_instruction(instruction)
	let b = ByteArray()
	b.pack_u32_le(code)
	let data = b.to_bytes()
	outstream.write_bytes(data)

fn gen_prologue(frame: Frame, out: BinaryOutput):
	# TODO: reserve stack space
	pass

fn gen_epilogue(frame: Frame, out: BinaryOutput):
	pass
