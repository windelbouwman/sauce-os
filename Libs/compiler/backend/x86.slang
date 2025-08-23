
"""
X86 instruction set
"""

from bytes import ByteArray
from outstream import BinaryOutput

pub enum Instruction:
	AddRmReg(rm: Rm, reg: int)
	AddRegRm(reg: int, rm: Rm)
	SubRmReg(rm: Rm, reg: int)
	SubRegRm(reg: int, rm: Rm)
	Call
	MovRmReg(rm: Rm, reg: int)
	MovRegRm(reg: int, rm: Rm)
	MovRegImm(reg: int, imm: int)
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
		MovRmReg(rm, reg):
			rm_reg_to_str("mov", rm, reg)
		MovRegRm(reg, rm):
			reg_rm_to_str("mov", reg, rm)
		MovRegImm(reg, imm):
			"mov {reg_to_str(reg)}, {imm}"
		Ret:
			"ret"

fn rm_reg_to_str(opcode?: str, rm: Rm, reg: int) -> str:
	"{opcode} {rm_to_str(rm)}, {reg_to_str(reg)}"

fn reg_rm_to_str(opcode?: str, reg: int, rm: Rm) -> str:
	"{opcode} {reg_to_str(reg)}, {rm_to_str(rm)}"

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

fn write_mod_rm_byte(mod: int, rm: int, reg: int, out: BinaryOutput):
	let mod_rm = (mod << 6) | (reg << 3) | rm
	out.write_byte(mod_rm)

fn write_mod_rm(opcode: int, rm: Rm, reg: int, out: BinaryOutput):
	out.write_byte(opcode)
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

pub fn emit_instruction(i: Instruction, out: BinaryOutput):
	case i:
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
		MovRmReg(rm, reg):
			write_mod_rm(opcode: 0x89, rm, reg, out)
		MovRegRm(reg, rm):
			write_mod_rm(opcode: 0x8B, rm, reg, out)
		MovRegImm(reg, imm):
			out.write_byte(0x48) # rex prefix
			out.write_byte(0xB8 + reg)
			write64(imm, out)
		Ret:
			out.write_byte(0xC3)
