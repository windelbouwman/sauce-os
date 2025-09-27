""" Turn bytecode into riscv code

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
from codegen import BackendV2, cgen, SelectionContextV2
from outstream import BinaryOutput
from utils import unimplemented
from logging import log_info

pub fn gen_riscv(program: sil.Program, filename: Option[str]):
	log_info("Generating riscv code")
	program.dump()
	let backend = BackendV2:
		selector: select_instruction
		materializer: materialize
		instruction_as_str: riscv.instruction_to_string
		to_binstream: do_emit
		emit_prologue: gen_prologue
		emit_epilogue: gen_epilogue

	unimplemented("TODO")
	# cgen(program, backend)

# class RiscvGen:
fn select_instruction(context: SelectionContextV2[riscv.Instruction], instruction: sil.Instruction):
	""" Select machine instruction based on sil operator """
	case instruction.op:
		Nop:
			context.emit(riscv.Instruction.ADDI(rd: 0, rs1: 0, imm: 0))
		Const(dst, value):
			unimplemented("Const")
		Jump(label):
			context.emit(riscv.Instruction.JAL(rd: 0, imm: 0))
		JumpNonZero(condition, label1, label2):
			context.emit(riscv.Instruction.JAL(rd: 0, imm: 0))
		Binop(dst, op2, lhs, rhs):
			case op2:
				Add:
					context.emit(riscv.Instruction.ADD(rd: 0, rs1: 0, rs2: 0))
				Sub:
					context.emit(riscv.Instruction.SUB(rd: 0, rs1: 0, rs2: 0))
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
						context.emit(riscv.Instruction.ADDI(rd: 7, rs1: 8, imm: 0))
					Global(name):
						context.emit(riscv.Instruction.LA(rd: 7, offset: 0))
				else:
					unimplemented("arg: {sil.value_to_string(argument)}")

			# Invoke function
			case callee:
				Global(name):
					context.emit(riscv.Instruction.JAL(rd: 1, imm: 0))
				Tmp(name):
					context.emit(riscv.Instruction.JALR(rd: 1, rs1: 9, imm: 0))
			else:
				unimplemented("Call: {sil.value_to_string(callee)}")

			# Eventually gather return value
			case dst:
				Some(value):
					pass
				None:
					pass
		Return(v):
			context.emit(riscv.Instruction.RET())
		Halt:
			context.emit(riscv.Instruction.EBREAK())
		Alloc(addr, size):
			# unimplemented("Alloc")
			pass
		Load(dst, addr):
			let offset = 0
			context.emit(riscv.Instruction.LW(rd: 0, rs1: 0, imm: offset))
		Store(addr, value):
			let offset = 0
			context.emit(riscv.Instruction.SW(rs1: 0, rs2: 0, imm: offset))

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



fn materialize(v: mil.Instruction[riscv.Instruction]) -> riscv.Instruction:
	""" Apply actual registers to instruction now. """
	case v.instruction:
		JAL(rd, imm):
			# rd = v.defs[0]
			riscv.Instruction.JAL(rd, imm)
	else:
		v.instruction

fn do_emit(instruction: riscv.Instruction, outstream: BinaryOutput):
	let code = riscv.encode_instruction(instruction)
	let b = ByteArray()
	b.pack_u32_le(code)
	let data = b.to_bytes()
	outstream.write_bytes(data)

fn gen_prologue(out: BinaryOutput):
	pass

fn gen_epilogue(out: BinaryOutput):
	pass
