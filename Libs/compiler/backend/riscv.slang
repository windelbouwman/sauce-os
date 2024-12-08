
# Idea for a RISCV backend.
# There are a couple of formats:
# R/I/S/U

from utils import panic


fn encode_R_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    # funct7[31-25]
    # rs2[24-20]
    # rs1[19-15]
    # funct3[14-12]
    # rd[11-7]
    # opcode[6-0]
    (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

fn encode_I_type(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    # imm[11:0][31-20]
    # rs1[19-15]
    # funct3[14-12]
    # rd[11-7]
    # opcode[6-0]
    (imm << 25) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

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
    # imm[31:12][31-12]
    # rd[11-7]
    # opcode[6-0]
    imm | (rd << 7) | (opcode)

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

    BEQ(rs1: int, rs2: int, imm: int)
    BNE(rs1: int, rs2: int, imm: int)
    BLT(rs1: int, rs2: int, imm: int)
    BGE(rs1: int, rs2: int, imm: int)
    BLTU(rs1: int, rs2: int, imm: int)
    BGEU(rs1: int, rs2: int, imm: int)

    LB(rd: int, rs1: int, imm: int)
    LH(rd: int, rs1: int, imm: int)
    LW(rd: int, rs1: int, imm: int)
    LBU(rd: int, rs1: int, imm: int)
    LHU(rd: int, rs1: int, imm: int)
    
    SB(rs1: int, rs2: int, imm: int)
    SH(rs1: int, rs2: int, imm: int)
    SW(rs1: int, rs2: int, imm: int)

    ADDI(rd: int, rs1: int, imm: int)
    SLTI(rd: int, rs1: int, imm: int)
    SLTIU(rd: int, rs1: int, imm: int)
    XORI(rd: int, rs1: int, imm: int)
    ORI(rd: int, rs1: int, imm: int)
    ANDI(rd: int, rs1: int, imm: int)
    SLLI(rd: int, rs1: int, imm: int)
    SRLI(rd: int, rs1: int, imm: int)
    SRAI(rd: int, rs1: int, imm: int)

    ADD(rd: int, rs1: int, rs2: int)
    SUB(rd: int, rs1: int, rs2: int)
    SLL(rd: int, rs1: int, rs2: int)
    SLT(rd: int, rs1: int, rs2: int)
    SLTU(rd: int, rs1: int, rs2: int)
    XOR(rd: int, rs1: int, rs2: int)
    SRL(rd: int, rs1: int, rs2: int)
    SRA(rd: int, rs1: int, rs2: int)
    OR(rd: int, rs1: int, rs2: int)
    AND(rd: int, rs1: int, rs2: int)

    # FENCE
    ECALL
    EBREAK

pub fn encode_instruction(instruction: Instruction) -> int:
    case instruction:
        LUI(rd, imm):
            encode_U_type(imm, rd, opcode: 0b0110111)
        AUIPC(rd, imm):
            encode_U_type(imm, rd, opcode: 0b0010111)
        JAL(rd, imm):
            encode_J_type(imm, rd, opcode: 0b1101111)
        JALR(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b000, rd, opcode: 0b1100111)

        BEQ(rs1, rs2, imm):
            encode_B_type(imm, rs2, rs1, funct3: 0b000, opcode: 0b1100011)
        BNE(rs1, rs2, imm):
            encode_B_type(imm, rs2, rs1, funct3: 0b001, opcode: 0b1100011)
        BLT(rs1, rs2, imm):
            encode_B_type(imm, rs2, rs1, funct3: 0b100, opcode: 0b1100011)
        BGE(rs1, rs2, imm):
            encode_B_type(imm, rs2, rs1, funct3: 0b101, opcode: 0b1100011)
        BLTU(rs1, rs2, imm):
            encode_B_type(imm, rs2, rs1, funct3: 0b110, opcode: 0b1100011)
        BGEU(rs1, rs2, imm):
            encode_B_type(imm, rs2, rs1, funct3: 0b111, opcode: 0b1100011)

        LB(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b000, rd, opcode: 0b0000011)
        LH(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b001, rd, opcode: 0b0000011)
        LW(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b010, rd, opcode: 0b0000011)
        LBU(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b100, rd, opcode: 0b0000011)
        LHU(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b101, rd, opcode: 0b0000011)

        SB(rs1, rs2, imm):
            encode_S_type(imm, rs2, rs1, funct3: 0b000, opcode: 0b0100011)
        SH(rs1, rs2, imm):
            encode_S_type(imm, rs2, rs1, funct3: 0b001, opcode: 0b0100011)
        SW(rs1, rs2, imm):
            encode_S_type(imm, rs2, rs1, funct3: 0b010, opcode: 0b0100011)

        ADDI(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b000, rd, opcode: 0b0010011)
        SLTI(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b010, rd, opcode: 0b0010011)
        SLTIU(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b011, rd, opcode: 0b0010011)
        XORI(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b100, rd, opcode: 0b0010011)
        ORI(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b110, rd, opcode: 0b0010011)
        ANDI(rd, rs1, imm):
            encode_I_type(imm, rs1, funct3: 0b111, rd, opcode: 0b0010011)
        SLLI(rd, rs1, imm):
            panic("shamt?")
        SRLI(rd, rs1, imm):
            panic("shamt?")
        SRAI(rd, rs1, imm):
            panic("shamt?")

        ADD(rd, rs1, rs2):
            encode_R_type(funct7: 0b0000000, rs2, rs1, funct3: 0b000, rd, opcode: 0b0110011)
        SUB(rd, rs1, rs2):
            encode_R_type(funct7: 0b0100000, rs2, rs1, funct3: 0b000, rd, opcode: 0b0110011)
        SLL(rd, rs1, rs2):
            encode_R_type(funct7: 0b0000000, rs2, rs1, funct3: 0b001, rd, opcode: 0b0110011)
        SLT(rd, rs1, rs2):
            encode_R_type(funct7: 0b0000000, rs2, rs1, funct3: 0b010, rd, opcode: 0b0110011)
        SLTU(rd, rs1, rs2):
            encode_R_type(funct7: 0b0000000, rs2, rs1, funct3: 0b011, rd, opcode: 0b0110011)
        XOR(rd, rs1, rs2):
            encode_R_type(funct7: 0b0000000, rs2, rs1, funct3: 0b100, rd, opcode: 0b0110011)
        SRL(rd, rs1, rs2):
            encode_R_type(funct7: 0b0000000, rs2, rs1, funct3: 0b101, rd, opcode: 0b0110011)
        SRA(rd, rs1, rs2):
            encode_R_type(funct7: 0b0100000, rs2, rs1, funct3: 0b101, rd, opcode: 0b0110011)
        OR(rd, rs1, rs2):
            encode_R_type(funct7: 0b0000000, rs2, rs1, funct3: 0b110, rd, opcode: 0b0110011)
        AND(rd, rs1, rs2):
            encode_R_type(funct7: 0b0000000, rs2, rs1, funct3: 0b111, rd, opcode: 0b0110011)

        # FENCE
        ECALL:
            encode_I_type(imm: 0b0, rs1: 0, funct3: 0, rd: 0, opcode: 0b1110011)
        EBREAK:
            encode_I_type(imm: 0b1, rs1: 0, funct3: 0, rd: 0, opcode: 0b1110011)


pub fn instruction_to_string(instruction: Instruction) -> str:
    case instruction:
        LUI(rd, imm):
            "lui x{rd}, {imm}"
        AUIPC(rd, imm):
            "auipc x{rd}, {imm}"
        JAL(rd, imm):
            "jal x{rd}, {imm}"
        JALR(rd, rs1, imm):
            "jalr x{rd}, x{rs1}, {imm}"

        BEQ(rs1, rs2, imm):
            "beq x{rs1}, x{rs2}, {imm}"
        BNE(rs1, rs2, imm):
            "bne x{rs1}, x{rs2}, {imm}"
        BLT(rs1, rs2, imm):
            "blt x{rs1}, x{rs2}, {imm}"
        BGE(rs1, rs2, imm):
            "bge x{rs1}, x{rs2}, {imm}"
        BLTU(rs1, rs2, imm):
            "bltu x{rs1}, x{rs2}, {imm}"
        BGEU(rs1, rs2, imm):
            "bgeu x{rs1}, x{rs2}, {imm}"

        LB(rd, rs1, imm):
            "lb x{rd}, x{rs1}, {imm}"
        LH(rd, rs1, imm):
            "lh x{rd}, x{rs1}, {imm}"
        LW(rd, rs1, imm):
            "lw x{rd}, x{rs1}, {imm}"
        LBU(rd, rs1, imm):
            "lbu x{rd}, x{rs1}, {imm}"
        LHU(rd, rs1, imm):
            "lhu x{rd}, x{rs1}, {imm}"

        SB(rs1, rs2, imm):
            "sb x{rs1}, x{rs2}, {imm}"
        SH(rs1, rs2, imm):
            "sh x{rs1}, x{rs2}, {imm}"
        SW(rs1, rs2, imm):
            "sw x{rs1}, x{rs2}, {imm}"

        ADDI(rd, rs1, imm):
            "addi x{rd}, x{rs1}, {imm}"
        SLTI(rd, rs1, imm):
            "slti x{rd}, x{rs1}, {imm}"
        SLTIU(rd, rs1, imm):
            "sltiu x{rd}, x{rs1}, {imm}"
        XORI(rd, rs1, imm):
            "xori x{rd}, x{rs1}, {imm}"
        ORI(rd, rs1, imm):
            "ori x{rd}, x{rs1}, {imm}"
        ANDI(rd, rs1, imm):
            "andi x{rd}, x{rs1}, {imm}"
        SLLI(rd, rs1, imm):
            "slli x{rd}, x{rs1}, {imm}"
        SRLI(rd, rs1, imm):
            "srli x{rd}, x{rs1}, {imm}"
        SRAI(rd, rs1, imm):
            "srai x{rd}, x{rs1}, {imm}"

        ADD(rd, rs1, rs2):
            "add x{rd}, x{rs1}, x{rs2}"
        SUB(rd, rs1, rs2):
            "sub x{rd}, x{rs1}, x{rs2}"
        SLL(rd, rs1, rs2):
            "sll x{rd}, x{rs1}, x{rs2}"
        SLT(rd, rs1, rs2):
            "slt x{rd}, x{rs1}, x{rs2}"
        SLTU(rd, rs1, rs2):
            "sltu x{rd}, x{rs1}, x{rs2}"
        XOR(rd, rs1, rs2):
            "xor x{rd}, x{rs1}, x{rs2}"
        SRL(rd, rs1, rs2):
            "srl x{rd}, x{rs1}, x{rs2}"
        SRA(rd, rs1, rs2):
            "sra x{rd}, x{rs1}, x{rs2}"
        OR(rd, rs1, rs2):
            "or x{rd}, x{rs1}, x{rs2}"
        AND(rd, rs1, rs2):
            "and x{rd}, x{rs1}, x{rs2}"

        # FENCE
        ECALL:
            "ecall"
        EBREAK:
            "ebreak"
