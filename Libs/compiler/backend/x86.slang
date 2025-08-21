
"""
X86 instruction set
"""

from outstream import BinaryOutput

pub enum Instruction:
	AddRmReg(rm: int, reg: int)
	SubRmReg(rm: int, reg: int)
	Call
	MovRmReg(rm: int, reg: int)
	MovRegRm(reg: int, rm: int)

pub fn instruction_to_string(instruction: Instruction) -> str:
	case instruction:
		AddRmReg(rm, reg):
			"add"
		SubRmReg(rm, reg):
			"sub"
		Call:
			"call"
		MovRmReg(rm, reg):
			"mov {rm}, {reg}"
		MovRegRm(reg, rm):
			"mov {reg}, {rm}"

pub struct X86Relocation:
	offset: int
	typ: X86RelocationType

enum X86RelocationType:
	R_NONE
	R_64(symbol: str, addend: int)
	R_PC32(symbol: str, addend: int)

fn write_mod_rm(mod: int, rm: int, reg: int, out: BinaryOutput):
	let mod_rm = (mod << 6) | (reg << 3) | rm
	out.write_byte(mod_rm)

pub fn emit_instruction(i: Instruction, out: BinaryOutput):
	case i:
		AddRmReg(rm, reg):
			out.write_byte(0x01)
			# write_mod_rm()
		SubRmReg(rm, reg):
			out.write_byte(0x29)
			# write_mod_rm()
		Call:
			out.write_byte(0x8E)
			out.write_byte(0)
			out.write_byte(0)
			out.write_byte(0)
			out.write_byte(0)
		MovRmReg(rm, reg):
			out.write_byte(0x89)
			write_mod_rm(mod: 0, rm, reg, out)
		MovRegRm(reg, rm):
			out.write_byte(0x8B)
			write_mod_rm(mod: 0, rm, reg, out)
