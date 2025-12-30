"""
RISCV encoding.

There are a couple of formats:
R/I/S/U

Register conventions:
register | name  | saver  | description
 x0      | zero  | -      | zero constant
 x1      | ra    | callee | return address
 x2      | sp    | callee | stack pointer
 x3      | gp    | -      | global pointer
 x4      | tp    | -      | thread pointer
 x5-x7   | t0-t2 | caller | temporaries
 x8      | s0/fp | callee | saved / frame pointer
 x9      | s1    | callee | saved register
 x10-x11 | a0-a1 | caller | function arguments / return values
 x12-x17 | a2-a7 | caller | function arguments
 x18-x27 | s2-s11| callee | Saved registers
 x28-x31 | t3-t6 | caller | temporaries
"""

from utils import panic, unimplemented
from bytes import ByteArray
from outstream import BinaryOutput

let R_BRANCH: int = 16
let R_JAL: int = 17
let R_CALL: int = 18
let R_HI20: int = 26
let R_LO12_I: int = 27

fn encode_R_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
	# funct7[31-25]  rs2[24-20]  rs1[19-15]  funct3[14-12]  rd[11-7]  opcode[6-0]
	(funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

fn encode_I_type(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
	# imm[11:0][31-20]  rs1[19-15]  funct3[14-12]  rd[11-7]  opcode[6-0]
	(imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

fn encode_S_type(imm: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
	# imm[11:5][31-25]
	# rs2[24-20]
	# rs1[19-15]
	# funct3[14-12]
	# imm[4:0][11-7]
	# opcode[6-0]
	let funct7 = imm >> 5
	let rd = imm & 0x1F
	encode_R_type(funct7, rs2, rs1, funct3, rd, opcode)

fn encode_U_type(imm: int, rd: int, opcode: int) -> int:
	# imm[31:12][31-12]  rd[11-7]  opcode[6-0]
	imm | (rd << 7) | opcode

fn encode_J_type(imm: int, rd: int, opcode: int) -> int:
	# special case of U type encoding
	imm =  ((imm & 0x100000) << 11) | ((imm & 0x7FE) << 20) | ((imm & 0x800) << 9) | (imm & 0xFF000)
	encode_U_type(imm, rd, opcode)

fn encode_B_type(imm: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
	# special case of S type encoding
	let funct7 = ((imm >> 6) & 0x40) | ((imm >> 5) & 0x3F)
	let rd = (imm & 0x1E) | ((imm >> 11) & 0x1)
	encode_R_type(funct7, rs2, rs1, funct3, rd, opcode)

pub enum Instruction:
	LUI(rd: int, imm: int)
	AUIPC(rd: int, imm: int)
	JAL(rd: int, imm: int)
	JALR(rd: int, rs1: int, imm: int)
	Branch(cond: Cond, rs1: int, rs2: int, label: str)
	Load(op: LoadOp, rd: int, rs1: int, imm: int)
	Store(op: StoreOp, rs1: int, rs2: int, imm: int)
	RegImm(op: ImmOp, rd: int, rs1: int, imm: int)
	SLLI(rd: int, rs1: int, imm: int)
	SRLI(rd: int, rs1: int, imm: int)
	SRAI(rd: int, rs1: int, imm: int)
	ThreeRegsOp(op: RegOp, rd: int, rs1: int, rs2: int)
	# FENCE
	ECALL
	EBREAK

	# Pseudo instructions
	LA(rd: int, symbol: str) # load address
	LI(rd: int, imm: int)  # Load immediate
	MOV(dst: int, src: int) # Move
	J(label: str)
	CALL(name: str)
	RET

pub enum Cond:
	EQ
	NE
	LT
	GE
	LTU
	GEU

pub enum LoadOp:
	LB
	LH
	LW
	LBU
	LHU

pub enum StoreOp:
	SB
	SH
	SW

pub enum ImmOp:
	ADDI
	SLTI
	SLTIU
	XORI
	ORI
	ANDI

pub enum RegOp:
	ADD
	SUB
	SLL
	SLT
	SLTU
	XOR
	SRL
	SRA
	OR
	AND

pub fn do_emit(instruction: Instruction, outstream: BinaryOutput):
	case instruction:
		LUI(rd, imm):
			emit_int_code(code: encode_U_type(imm, rd, opcode: 0b0110111), outstream)
		AUIPC(rd, imm):
			emit_int_code(code: encode_U_type(imm, rd, opcode: 0b0010111), outstream)
		JAL(rd, imm):
			emit_int_code(code: encode_J_type(imm, rd, opcode: 0b1101111), outstream)
		JALR(rd, rs1, imm):
			emit_int_code(code: encode_I_type(imm, rs1, funct3: 0b000, rd, opcode: 0b1100111), outstream)
		Branch(cond, rs1, rs2, label):
			outstream.add_fixup(symbol: label, typ: R_BRANCH, addend: 0)
			emit_int_code(code: encode_B_type(imm: 0, rs2, rs1, funct3: cond_code(cond), opcode: 0b1100011), outstream)
		Load(op, rd, rs1, imm):
			emit_int_code(code: encode_I_type(imm, rs1, funct3: load_op_code(op), rd, opcode: 0b0000011), outstream)
		Store(op, rs1, rs2, imm):
			emit_int_code(code: encode_S_type(imm, rs2, rs1, funct3: store_op_code(op), opcode: 0b0100011), outstream)
		RegImm(op, rd, rs1, imm):
			emit_int_code(code: encode_I_type(imm, rs1, funct3: imm_op_code(op), rd, opcode: 0b0010011), outstream)
		SLLI(rd, rs1, imm):
			panic("shamt?")
		SRLI(rd, rs1, imm):
			panic("shamt?")
		SRAI(rd, rs1, imm):
			panic("shamt?")
		ThreeRegsOp(op, rd, rs1, rs2):
			let funct7 = case op:
				ADD: 0b0000000
				SUB: 0b0100000
				SLL: 0b0000000
				SLT: 0b0000000
				SLTU: 0b0000000
				XOR: 0b0000000
				SRL: 0b0000000
				SRA: 0b0100000
				OR: 0b0000000
				AND: 0b0000000
			emit_int_code(code: encode_R_type(funct7, rs2, rs1, funct3: reg_op_code(op), rd, opcode: 0b0110011), outstream)
		# FENCE
		ECALL:
			emit_int_code(code: encode_I_type(imm: 0, rs1: 0, funct3: 0, rd: 0, opcode: 0b1110011), outstream)
		EBREAK:
			emit_int_code(code: encode_I_type(imm: 1, rs1: 0, funct3: 0, rd: 0, opcode: 0b1110011), outstream)
		LA(rd, name):
			outstream.add_fixup(symbol: name, typ: R_HI20, addend: 0)
			do_emit(instruction: Instruction.LUI(rd, imm: 0), outstream)
			outstream.add_fixup(symbol: name, typ: R_LO12_I, addend: 0)
			do_emit(instruction: Instruction.RegImm(op: ImmOp.ADDI(), rd, rs1: rd, imm: 0), outstream)
		LI(rd, imm):
			if imm > -1000 and imm < 1000:
				# Small constants can use only ADDI
				do_emit(instruction: Instruction.RegImm(op: ImmOp.ADDI(), rd, rs1: 0, imm: imm), outstream)
			else:
				# TODO: logic below not ok?
				let low_imm = imm & 0xFFF
				var high_imm = (imm >> 12) << 12
				if low_imm > 0x7ff:
					high_imm += 1
				do_emit(instruction: Instruction.LUI(rd, imm: high_imm), outstream)
				do_emit(instruction: Instruction.RegImm(op: ImmOp.ADDI(), rd, rs1: rd, imm: low_imm), outstream)
		MOV(dst, src):
			do_emit(instruction: Instruction.RegImm(op: ImmOp.ADDI(), rd: dst, rs: src, imm: 0), outstream)
		J(label):
			outstream.add_fixup(symbol: label, typ: R_JAL, addend: 0)
			do_emit(instruction: Instruction.JAL(rd: 0, imm: 0), outstream)
		CALL(name):
			outstream.add_fixup(symbol: name, typ: R_CALL, addend: 0)
			do_emit(instruction: Instruction.AUIPC(rd: 1, imm: 0), outstream)
			do_emit(instruction: Instruction.JALR(rd: 1, rs: 1, imm: 0), outstream)
		RET:
			do_emit(instruction: Instruction.JALR(rd: 0, rs: 1, imm: 0), outstream)

fn emit_int_code(code: int, outstream: BinaryOutput):
	outstream.write_u32_le(code)

fn cond_code(cond: Cond) -> int:
	case cond:
		EQ: 0b000
		NE: 0b001
		LT: 0b100
		GE: 0b101
		LTU: 0b110
		GEU: 0b111

fn imm_op_code(op: ImmOp) -> int:
	case op:
		ADDI: 0b000
		SLTI: 0b010
		SLTIU: 0b011
		XORI: 0b100
		ORI: 0b110
		ANDI: 0b111

fn reg_op_code(op: RegOp) -> int:
	case op:
		ADD: 0b000
		SUB: 0b000
		SLL: 0b001
		SLT: 0b010
		SLTU: 0b011
		XOR: 0b100
		SRL: 0b101
		SRA: 0b101
		OR: 0b110
		AND: 0b111

fn load_op_code(op: LoadOp) -> int:
	case op:
		LB: 0b000
		LH: 0b001
		LW: 0b010
		LBU: 0b100
		LHU: 0b101

fn store_op_code(op: StoreOp) -> int:
	case op:
		SB: 0b000
		SH: 0b001
		SW: 0b010

pub fn instruction_to_string(instruction: Instruction) -> str:
	case instruction:
		LUI(rd, imm): "lui {reg_to_string(rd)}, {imm}"
		AUIPC(rd, imm): "auipc {reg_to_string(rd)}, {imm}"
		JAL(rd, imm): "jal {reg_to_string(rd)}, {imm}"
		JALR(rd, rs1, imm): "jalr {reg_to_string(rd)}, {reg_to_string(rs1)}, {imm}"
		Branch(cond, rs1, rs2, label):
			"b{cond_to_string(cond)} {reg_to_string(rs1)}, {reg_to_string(rs2)}, {label}"
		Load(op, rd, rs1, imm):
			"{load_op_to_string(op)} {reg_to_string(rd)}, {imm}({reg_to_string(rs1)})"
		Store(op, rs1, rs2, imm):
			"{store_op_to_string(op)} {reg_to_string(rs2)}, {imm}({reg_to_string(rs1)})"
		RegImm(op, rd, rs1, imm):
			"{imm_op_to_string(op)} {reg_to_string(rd)}, {reg_to_string(rs1)}, {imm}"
		SLLI(rd, rs1, imm):
			"slli {reg_to_string(rd)}, {reg_to_string(rs1)}, {imm}"
		SRLI(rd, rs1, imm):
			"srli {reg_to_string(rd)}, {reg_to_string(rs1)}, {imm}"
		SRAI(rd, rs1, imm):
			"srai {reg_to_string(rd)}, {reg_to_string(rs1)}, {imm}"
		ThreeRegsOp(op, rd, rs1, rs2):
			"{reg_op_to_string(op)} {reg_to_string(rd)}, {reg_to_string(rs1)}, {reg_to_string(rs2)}"
		ECALL: "ecall"
		EBREAK: "ebreak"
		LA(rd, name): "la {reg_to_string(rd)}, {name}"
		LI(rd, value): "li {reg_to_string(rd)}, {value}"
		MOV(dst, src): "mv {reg_to_string(dst)},{reg_to_string(src)}"
		J(label): "j {label}"
		CALL(name): "call {name}"
		RET: "ret"

pub fn cond_to_string(cond: Cond) -> str:
	case cond:
		EQ: "eq"
		NE: "ne"
		LT: "lt"
		GE: "ge"
		LTU: "ltu"
		GEU: "geu"

pub fn imm_op_to_string(op: ImmOp) -> str:
	case op:
		ADDI: "addi"
		SLTI: "slti"
		SLTIU: "sltiu"
		XORI: "xori"
		ORI: "ori"
		ANDI: "andi"

pub fn reg_op_to_string(op: RegOp) -> str:
	case op:
		ADD: "add"
		SUB: "sub"
		SLL: "sll"
		SLT: "slt"
		SLTU: "sltu"
		XOR: "xor"
		SRL: "srl"
		SRA: "sra"
		OR: "or"
		AND: "and"

pub fn load_op_to_string(op: LoadOp) -> str:
	case op:
		LB: "lb"
		LH: "lh"
		LW: "lw"
		LBU: "lbu"
		LHU: "lhu"

pub fn store_op_to_string(op: StoreOp) -> str:
	case op:
		SB: "sb"
		SH: "sh"
		SW: "sw"

fn reg_to_string(reg?: int) -> str:
	switch reg:
		0: "zero"
		1: "ra"
		2: "sp"
		3: "gp"
		4: "tp"
		5: "t0"
		6: "t1"
		7: "t2"
		8: "fp"
		9: "s1"
		10: "a0"
		11: "a1"
		12: "a2"
		13: "a3"
		14: "a4"
		15: "a5"
		16: "a6"
		17: "a7"
		18: "s2"
		19: "s3"
		20: "s4"
		21: "s5"
		22: "s6"
		23: "s7"
		24: "s8"
		25: "s9"
		26: "s10"
		27: "s11"
		28: "t3"
		29: "t4"
		30: "t5"
		31: "t6"
	else:
		"x{reg}"

pub enum Relocation:
	Abs64(name: str)

pub fn is_pic_reloc(typ: int) -> bool:
	""" Check if the relocation type is position independant """
	if typ == R_BRANCH or typ == R_JAL:
		true
	else:
		false

pub fn apply_reloc(data: ByteArray, offset: int, typ: int, addend: int, symbol: int):
	switch typ:
		R_BRANCH:
			let old = read_int_at(data, offset)
			let value = symbol + addend - offset
			# TODO: merge the bit fiddling below with the encode functions on top?
			let funct7 = ((value >> 6) & 0x40) | ((value >> 5) & 0x3F)
			let rd = (value & 0x1E) | ((value >> 11) & 0x1)
			let patched = old | (rd << 7) | (funct7 << 25)
			write_int_at(data, offset, value: patched)
		R_JAL:
			let old = read_int_at(data, offset)
			let value = symbol + addend - offset
			let shuffled = ((value & 0x100000) << 11) | ((value & 0x7FE) << 20) | ((value & 0x800) << 9) | (value & 0xFF000)
			let patched = (old & 0xFFF) | shuffled
			write_int_at(data, offset, value: patched)
	else:
		unimplemented("riscv reloc {typ}")

fn read_int_at(data: ByteArray, offset: int) -> int:
	data.get(index: offset + 0) | (data.get(index: offset + 1) << 8) | (data.get(index: offset + 2) << 16) | (data.get(index: offset + 3) << 24)

fn write_int_at(data: ByteArray, offset: int, value: int):
	data.set(index: offset + 0, value: value & 0xFF)
	data.set(index: offset + 1, value: (value >> 8) & 0xFF)
	data.set(index: offset + 2, value: (value >> 16) & 0xFF)
	data.set(index: offset + 3, value: (value >> 24) & 0xFF)
