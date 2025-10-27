"""
X86 instruction set

Calling conventions 64 bit / system V ABI

arguments: rdi, rsi, rdx, rcx, r8, r9
return value: rax

callee save registers: rbx, rsp, rbp, r12, r13, r14, r15
caller save: the other registers

"""

from bytes import ByteArray
from outstream import BinaryOutput

pub enum Instruction:
	AddRmReg(rm: Rm, reg: int)
	AddRegRm(reg: int, rm: Rm)
	SubRmReg(rm: Rm, reg: int)
	SubRegRm(reg: int, rm: Rm)
	Call
	AddRmImm(rm: Rm, imm: int)
	SubRmImm(rm: Rm, imm: int)
	MovRmReg(rm: Rm, reg: int)
	MovRegRm(reg: int, rm: Rm)
	MovRegImm(reg: int, imm: int)
	Push(reg: int)
	Pop(reg: int)
	Ret

pub enum Rm:
	Mem(reg: int)
	MemDisp8(reg: int, disp: int)
	MemDisp32(reg: int, disp: int)
	Reg(reg: int)

pub fn instruction_to_string(instruction: Instruction) -> str:
	case instruction:
		AddRmReg(rm, reg):
			rm_reg_to_str("add", rm, reg)
		AddRegRm(reg, rm):
			reg_rm_to_str("add", reg, rm)
		SubRmReg(rm, reg):
			rm_reg_to_str("sub", rm, reg)
		SubRegRm(reg, rm):
			reg_rm_to_str("sub", reg, rm)
		Call:
			"call"
		AddRmImm(rm, imm):
			rm_imm_to_str("add", rm, imm)
		SubRmImm(rm, imm):
			rm_imm_to_str("sub", rm, imm)
		MovRmReg(rm, reg):
			rm_reg_to_str("mov", rm, reg)
		MovRegRm(reg, rm):
			reg_rm_to_str("mov", reg, rm)
		MovRegImm(reg, imm):
			"mov {reg_to_str(reg)}, {imm}"
		Push(reg):
			"push {reg_to_str(reg)}"
		Pop(reg):
			"pop {reg_to_str(reg)}"
		Ret:
			"ret"

fn rm_reg_to_str(opcode?: str, rm: Rm, reg: int) -> str:
	"{opcode} {rm_to_str(rm)}, {reg_to_str(reg)}"

fn reg_rm_to_str(opcode?: str, reg: int, rm: Rm) -> str:
	"{opcode} {reg_to_str(reg)}, {rm_to_str(rm)}"

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
		Reg(reg):
			reg_to_str(reg)

fn reg64_to_str(reg: int) -> str:
	switch reg:
		0:
			"rax"
		1:
			"rcx"
		2:
			"rdx"
		3:
			"rbx"
		4:
			"rsp"
		5:
			"rbp"
		6:
			"rsi"
		7:
			"rdi"
	else:
		"?{reg}"

fn reg_to_str(reg: int) -> str:
	switch reg:
		0:
			"eax"
		1:
			"ecx"
		2:
			"edx"
		3:
			"ebx"
		4:
			"esp"
		5:
			"ebp"
		6:
			"esi"
		7:
			"edi"
	else:
		"?{reg}"

fn reg16_to_str(reg: int) -> str:
	switch reg:
		0:
			"ax"
		1:
			"cx"
		2:
			"dx"
		3:
			"bx"
		4:
			"sp"
		5:
			"bp"
		6:
			"si"
		7:
			"di"
	else:
		"?{reg}"

fn reg8_to_str(reg: int) -> str:
	switch reg:
		0:
			"al"
		1:
			"cl"
		2:
			"dl"
		3:
			"bl"
		4:
			"ah"
		5:
			"ch"
		6:
			"dh"
		7:
			"bh"
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

fn write_rex_byte(out: BinaryOutput):
	out.write_byte(0x48) # rex prefix

fn write_mod_rm_byte(mod: int, rm: int, reg: int, out: BinaryOutput):
	let mod_rm = (mod << 6) | (reg << 3) | rm
	out.write_byte(mod_rm)

fn write_mod_rm(opcode: int, rm: Rm, reg: int, out: BinaryOutput):
	write_rex_byte(out)
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
		Reg(reg2):
			write_mod_rm_byte(mod: 3, rm: reg2, reg, out)

fn write_rm_imm(reg: int, rm: Rm, imm: int, out: BinaryOutput):
	write_rex_byte(out)
	out.write_byte(0x81)
	write_rm_reg(rm, reg, out)
	write32(imm, out)

pub fn emit_instruction(instruction?: Instruction, out: BinaryOutput):
	case instruction:
		AddRmReg(rm, reg):
			write_mod_rm(opcode: 0x01, rm, reg, out)
		AddRegRm(reg, rm):
			write_mod_rm(opcode: 0x03, rm, reg, out)
		SubRmReg(rm, reg):
			write_mod_rm(opcode: 0x29, rm, reg, out)
		SubRegRm(reg, rm):
			write_mod_rm(opcode: 0x2B, rm, reg, out)
		Call:
			out.write_byte(0x8E)
			write32(0, out)
		AddRmImm(rm, imm):
			write_rm_imm(reg: 0, rm, imm, out)
		SubRmImm(rm, imm):
			write_rm_imm(reg: 5, rm, imm, out)
		MovRmReg(rm, reg):
			write_mod_rm(opcode: 0x89, rm, reg, out)
		MovRegRm(reg, rm):
			write_mod_rm(opcode: 0x8B, rm, reg, out)
		MovRegImm(reg, imm):
			write_rex_byte(out)
			out.write_byte(0xB8 + reg)
			write64(imm, out)
		Push(reg):
			out.write_byte(0x50 + reg)
		Pop(reg):
			out.write_byte(0x58 + reg)
		Ret:
			out.write_byte(0xC3)
