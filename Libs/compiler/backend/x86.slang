"""
X86 instruction set

Calling conventions 64 bit / system V ABI

arguments:    rdi, rsi, rdx, rcx, r8, r9
return value: rax
callee save:  rbx, rsp, rbp, r12, r13, r14, r15
caller save:  the other registers

SSE (linux/mac/unix):
arguments: xmm0 .. xmm7
return value: xmm0
callee save: -
caller save: xmm0 .. xmm15
"""

from utils import unimplemented, panic
from bytes import ByteArray
from outstream import BinaryOutput

let R_X86_64_NONE: int = 0
let R_X86_64_64: int = 1  # S + A
let R_X86_64_PC32: int = 2 # S + A - P
let R_X86_64_GOT32: int = 3 # G + A
let R_X86_64_PLT32: int = 4 # L + A - P
let R_X86_64_32: int = 10  # S + A
let R_X86_64_16: int = 12  # S + A

pub enum Instruction:
	OpRmReg(op: Op, rm: Rm, reg: int)
	OpRegRm(op: Op, reg: int, rm: Rm)
	MulRegRm(reg: int, rm: Rm)
	Cqo
	DivMul(op: DivMulOp, rm: Rm)  # mul,imul,div,idiv
	Call(target: str)
	CallRm(rm: Rm)
	Jmp(target: str)
	Jcc(condition: Cond, target: str)
	AddRmImm(rm: Rm, imm: int)
	SubRmImm(rm: Rm, imm: int)
	ShiftRmCl(op: ShiftOp, rm: Rm)
	Lea(reg: int, rm: Rm)
	MovRegImm64(reg: int, imm: int)
	MovRegImm32(reg: int, imm: int)
	Push(reg: int)
	Pop(reg: int)
	Ret
	Int3
	CvtSi2Sd(reg: int, rm: Rm)
	CvtSd2Si(reg: int, rm: Rm)
	Ucomisd(reg: int, rm: Rm)
	SseOpRegRm(op: SseOp, reg: int, rm: Rm)
	SseMovRegRm(reg: int, rm: Rm)
	SseMovRmReg(rm: Rm, reg: int)

pub enum Op:
	Add
	Sub
	Cmp
	And
	Or
	Xor
	Mov

pub enum Cond:
	Jb
	Jae
	Jz
	Jnz
	Jbe
	Ja
	Jl
	Jge
	Jle
	Jg

pub enum SseOp:
	Add
	Mul
	Sub
	Min
	Div
	Max

pub enum DivMulOp:
	Mul
	IMul
	Div
	IDiv

pub enum ShiftOp:
	Rol
	Ror
	Rcl
	Rcr
	Shl
	Shr
	Sar

pub enum Rm:
	Mem(reg: int)
	MemDisp8(reg: int, disp: int)
	MemDisp32(reg: int, disp: int)
	RipDisp32(name: str)
	Reg(reg: int)

pub fn instruction_to_string(instruction: Instruction) -> str:
	case instruction:
		OpRmReg(op, rm, reg):
			rm_reg_to_str(op_to_str(op), rm, reg)
		OpRegRm(op, reg, rm):
			reg_rm_to_str(op_to_str(op), reg, rm)
		MulRegRm(reg, rm):
			reg_rm_to_str("mul", reg, rm)
		Cqo:
			"cqo"
		DivMul(op, rm):
			"{div_mul_op_to_str(op)} {rm_to_str(rm)}"
		Call(target):
			"call {target}"
		CallRm(rm):
			"call {rm_to_str(rm)}"
		Jmp(target):
			"jmp {target}"
		Jcc(condition, target):
			"{cc_to_string(condition)} {target}"
		AddRmImm(rm, imm):
			rm_imm_to_str("add", rm, imm)
		SubRmImm(rm, imm):
			rm_imm_to_str("sub", rm, imm)
		ShiftRmCl(op, rm):
			"{shift_op_to_string(op)} {rm_to_str(rm)}, cl"
		Lea(reg, rm):
			"lea {reg_to_str(reg)}, {rm_to_str(rm)}"
		MovRegImm64(reg, imm):
			"mov {reg_to_str(reg)}, {imm}"
		MovRegImm32(reg, imm):
			"mov {reg_to_str(reg)}, {imm}"
		Push(reg):
			"push {reg_to_str(reg)}"
		Pop(reg):
			"pop {reg_to_str(reg)}"
		Ret:
			"ret"
		Int3:
			"int 3"
		CvtSi2Sd(reg, rm):
			"cvtsi2sd .."
		CvtSd2Si(reg, rm):
			"cvtsd2si .."
		Ucomisd(reg, rm):
			"comisd ..."
		SseOpRegRm(op, reg, rm):
			"{sse_op_to_str(op)}sd {reg_to_str(reg)}, {rm_to_str(rm)}"
		SseMovRegRm(reg, rm):
			"movsd {reg_to_str(reg)}, {rm_to_str(rm)}"
		SseMovRmReg(rm, reg):
			"movsd {rm_to_str(rm)}, {reg_to_str(reg)}"

pub fn div_mul_op_to_str(op: DivMulOp) -> str:
	case op:
		Mul: "mul"
		IMul: "imul"
		Div: "div"
		IDiv: "idiv"

fn sse_op_to_str(op: SseOp) -> str:
	case op:
		Add: "add"
		Mul: "mul"
		Sub: "sub"
		Min: "min"
		Div: "div"
		Max: "max"

pub fn op_to_str(op: Op) -> str:
	case op:
		Add: "add"
		Sub: "sub"
		Cmp: "cmp"
		And: "and"
		Or: "or"
		Xor: "xor"
		Mov: "mov"

fn cc_to_string(condition: Cond) -> str:
	case condition:
		Jb: "jb"
		Jae: "jae"
		Jz: "jz"
		Jnz: "jnz"
		Jbe: "jbe"
		Ja: "ja"
		Jl: "jl"
		Jge: "jge"
		Jle: "jle"
		Jg: "jg"

pub fn shift_op_to_string(op: ShiftOp) -> str:
	case op:
		Rol: "rol"
		Ror: "ror"
		Rcl: "rcl"
		Rcr: "rcr"
		Shl: "shl"
		Shr: "shr"
		Sar: "sar"

fn rm_reg_to_str(mnemonic?: str, rm: Rm, reg: int) -> str:
	"{mnemonic} {rm_to_str(rm)}, {reg_to_str(reg)}"

fn reg_rm_to_str(mnemonic?: str, reg: int, rm: Rm) -> str:
	"{mnemonic} {reg_to_str(reg)}, {rm_to_str(rm)}"

fn rm_imm_to_str(opcode?: str, rm: Rm, imm: int) -> str:
	"{opcode} {rm_to_str(rm)}, {imm}"

fn rm_to_str(rm: Rm) -> str:
	case rm:
		Mem(reg):
			"[{reg_to_str(reg)}]"
		MemDisp8(reg, disp):
			"[{reg_to_str(reg)} + {disp}]"
		MemDisp32(reg, disp):
			"[{reg_to_str(reg)} + {disp}]"
		RipDisp32(name):
			"[{name}]"
		Reg(reg):
			reg_to_str(reg)

fn reg64_to_str(reg: int) -> str:
	switch reg:
		0: "rax"
		1: "rcx"
		2: "rdx"
		3: "rbx"
		4: "rsp"
		5: "rbp"
		6: "rsi"
		7: "rdi"
		8: "r8"
		9: "r9"
		10: "r10"
		11: "r11"
		12: "r12"
		13: "r13"
		14: "r14"
		15: "r15"
	else:
		"?{reg}"

fn reg_to_str(reg: int) -> str:
	switch reg:
		0: "eax"
		1: "ecx"
		2: "edx"
		3: "ebx"
		4: "esp"
		5: "ebp"
		6: "esi"
		7: "edi"
	else:
		"er{reg}"

fn reg16_to_str(reg: int) -> str:
	switch reg:
		0: "ax"
		1: "cx"
		2: "dx"
		3: "bx"
		4: "sp"
		5: "bp"
		6: "si"
		7: "di"
	else:
		"?{reg}"

fn reg8_to_str(reg: int) -> str:
	switch reg:
		0: "al"
		1: "cl"
		2: "dl"
		3: "bl"
		4: "ah"
		5: "ch"
		6: "dh"
		7: "bh"
	else:
		"?{reg}"

pub struct X86Relocation:
	offset: int
	typ: X86RelocationType

enum X86RelocationType:
	R_NONE
	R_64(symbol: str, addend: int)
	R_PC32(symbol: str, addend: int)

fn write32(value?: int, out: BinaryOutput):
	let x = ByteArray()
	x.pack_u32_le(value)
	out.write_bytes(data: x.to_bytes())

fn write64(value?: int, out: BinaryOutput):
	let x = ByteArray()
	x.pack_u64_le(value)
	out.write_bytes(data: x.to_bytes())

fn write_rex_byte(out: BinaryOutput, reg: int):
	# var b = 0x48
	# if rm > 7:
	# 	panic("rm > 7")
	# if rm < 0:
	# 	panic("rm < 0")
	if reg > 7:
		panic("reg > 7")
	if reg < 0:
		panic("reg < 0")
	# let r = (reg >> 3) << 2
	out.write_byte(0x48) # rex prefix

fn write_mod_rm_byte(mod: int, rm: int, reg: int, out: BinaryOutput):
	if rm > 7:
		panic("rm > 7")
	if rm < 0:
		panic("rm < 0")
	if reg > 7:
		panic("reg > 7")
	if reg < 0:
		panic("reg < 0")
	let mod_rm = (mod << 6) | (reg << 3) | rm
	out.write_byte(mod_rm)

fn write_mod_rm(opcode: int, rm: Rm, reg: int, out: BinaryOutput):
	write_rex_byte(out, reg)
	out.write_byte(opcode)
	write_rm_reg(rm, reg, out)

fn write_rm_reg(rm: Rm, reg: int, out: BinaryOutput):
	case rm:
		Mem(reg2):
			write_mod_rm_byte(mod: 0, rm: reg2, reg, out)
		MemDisp8(reg2, disp):
			write_mod_rm_byte(mod: 1, rm: reg2, reg, out)
			out.write_byte(disp)
		MemDisp32(reg2, disp):
			write_mod_rm_byte(mod: 2, rm: reg2, reg, out)
			write32(disp, out)
		RipDisp32(name):
			write_mod_rm_byte(mod: 0, rm: 5, reg, out)
			out.add_fixup(symbol: name, typ: R_X86_64_PC32, addend: -4)
			write32(0, out)
		Reg(reg2):
			write_mod_rm_byte(mod: 3, rm: reg2, reg, out)

fn write_rm_imm(reg: int, rm: Rm, imm: int, out: BinaryOutput):
	write_rex_byte(out, reg)
	out.write_byte(0x81)
	write_rm_reg(rm, reg, out)
	write32(imm, out)

pub fn emit_instruction(instruction?: Instruction, out: BinaryOutput):
	case instruction:
		OpRmReg(op, rm, reg):
			let opcode = get_opcode(op) + 1
			write_mod_rm(opcode, rm, reg, out)
		OpRegRm(op, reg, rm):
			let opcode = get_opcode(op) + 3
			write_mod_rm(opcode, rm, reg, out)
		MulRegRm(reg, rm):
			write_rex_byte(out, reg)
			out.write_byte(0x0F)
			out.write_byte(0xAF)
			write_rm_reg(rm, reg, out)
		Cqo:
			out.write_byte(0x48)
			out.write_byte(0x99)
		DivMul(op, rm):
			let reg = case op:
				Mul:
					4
				IMul:
					5
				Div:
					6
				IDiv:
					7
			write_rex_byte(out, reg)
			out.write_byte(0xf7)
			write_rm_reg(rm, reg, out)
		Call(target):
			out.write_byte(0xE8)
			out.add_fixup(symbol: target, typ: R_X86_64_PC32, addend: -4)
			write32(0, out)
		CallRm(rm):
			# FF /2
			let reg = 2
			write_rex_byte(out, reg)
			out.write_byte(0xFF)
			write_rm_reg(rm, reg, out)
		Jmp(target):
			# EB = short jump, E9 = near jump
			out.write_byte(0xE9)
			out.add_fixup(symbol: target, typ: R_X86_64_PC32, addend: -4)
			write32(0, out)
		Jcc(condition, target):
			# Near jumps
			out.write_byte(0x0F)
			out.write_byte(0x80 + get_cc_code(condition))
			out.add_fixup(symbol: target, typ: R_X86_64_PC32, addend: -4)
			write32(0, out)
		AddRmImm(rm, imm):
			write_rm_imm(reg: 0, rm, imm, out)
		SubRmImm(rm, imm):
			write_rm_imm(reg: 5, rm, imm, out)
		ShiftRmCl(op, rm):
			let reg = get_shift_code(op)
			write_rex_byte(out, reg)
			out.write_byte(0xD3)
			write_rm_reg(rm, reg, out)
		Lea(reg, rm):
			write_mod_rm(opcode: 0x8D, rm, reg, out)
		MovRegImm64(reg, imm):
			write_rex_byte(out, reg)
			out.write_byte(0xB8 + reg)
			write64(imm, out)
		MovRegImm32(reg, imm):
			out.write_byte(0xB8 + reg)
			write32(imm, out)
		Push(reg):
			out.write_byte(0x50 + reg)
		Pop(reg):
			out.write_byte(0x58 + reg)
		Ret:
			out.write_byte(0xC3)
		Int3:
			out.write_byte(0xCC)
		CvtSi2Sd(reg, rm):
			out.write_byte(0xF2)
			write_rex_byte(out, reg)
			out.write_byte(0x0F)
			out.write_byte(0x2A)
			write_rm_reg(rm, reg, out)
		CvtSd2Si(reg, rm):
			out.write_byte(0xF2)
			write_rex_byte(out, reg)
			out.write_byte(0x0F)
			out.write_byte(0x2D)
			write_rm_reg(rm, reg, out)
		Ucomisd(reg, rm):
			out.write_byte(0x66)
			# Only required when reg > 7:
			# write_rex_byte(out, reg)
			out.write_byte(0x0F)
			out.write_byte(0x2E)
			write_rm_reg(rm, reg, out)
		SseOpRegRm(op, reg, rm):
			out.write_byte(0xF2)
			out.write_byte(0x0F)
			out.write_byte(get_sse_opcode(op))
			write_rm_reg(rm, reg, out)
		SseMovRegRm(reg, rm):
			out.write_byte(0xF2)
			out.write_byte(0x0F)
			out.write_byte(0x10)
			write_rm_reg(rm, reg, out)
		SseMovRmReg(rm, reg):
			out.write_byte(0xF2)
			out.write_byte(0x0F)
			out.write_byte(0x11)
			write_rm_reg(rm, reg, out)

fn get_sse_opcode(op: SseOp) -> int:
	case op:
		Add: 0x58
		Mul: 0x59
		Sub: 0x5C
		Min: 0x5D
		Div: 0x5E
		Max: 0x5F

fn get_opcode(op: Op) -> int:
	case op:
		Add: 0x0
		Or: 0x8
		# ADC: 0x10
		# SBB: 0x18
		And: 0x20
		Sub: 0x28
		Xor: 0x30
		Cmp: 0x38
		Mov: 0x88

fn get_cc_code(condition: Cond) -> int:
	case condition:
		Jb: 0x2
		Jae: 0x3
		Jz: 0x4
		Jnz: 0x5
		Jbe: 0x6
		Ja: 0x7
		Jl: 0xC
		Jge: 0xD
		Jle: 0xE
		Jg: 0xF

fn get_shift_code(op: ShiftOp) -> int:
	case op:
		Rol: 0
		Ror: 1
		Rcl: 2
		Rcr: 3
		Shl: 4
		Shr: 5
		Sar: 7

pub fn is_pic_reloc(typ: int) -> bool:
	switch typ:
		2:  # PC32
			true
	else:
		false

pub fn apply_reloc(data: ByteArray, offset: int, typ: int, addend: int, symbol: int):
	# log_info
	switch typ:
		2:  # PC32
			let value = symbol + addend - offset
			data.set(index: offset + 0, value: value & 0xFF)
			data.set(index: offset + 1, value: (value >> 8) & 0xFF)
			data.set(index: offset + 2, value: (value >> 16) & 0xFF)
			data.set(index: offset + 3, value: (value >> 24) & 0xFF)
	else:
		unimplemented("reloc type: {typ}")

pub fn emit_pointer_to_name(name: str, out: BinaryOutput):
	out.add_fixup(symbol: name, typ: R_X86_64_64, addend: 0)
	out.write_byte(0x0)
	out.write_byte(0x0)
	out.write_byte(0x0)
	out.write_byte(0x0)

	out.write_byte(0x0)
	out.write_byte(0x0)
	out.write_byte(0x0)
	out.write_byte(0x0)
