
# Turn bytecode into riscv code

# Register usage convention:    (saver)
# x0 -> zero -> hardwired 0
# x1 -> ra   -> return address  (caller)
# x2 -> sp   -> stack pointer   (caller)
# x3 -> gp   -> global pointer
# x4 -> tp   -> thread pointer
# x5-x7      -> temporaries     (caller)
# x8
# x9
# x18-x27 -> s2-11 -> saved registers (callee)
# x28-31 -> t3-6 -> temporaries (caller)

# Pseudo instructions:
# NOP  > ADDI x0, x0, 0
# RET  > JALR x0, 0(ra)
# J offset  > JAL x0, offset
# MV rd, rs  > ADDI rd, rs, 0

import bc
from std import print, chr, ord
import riscv
from vectype import Vector, new_vector
from utils import panic, log_info
from strlib import int_to_hex_string
from hexfile import HexFile
from bytes import ByteArray

fn gen_riscv(program: bc.Program):
    log_info("Generating riscv code")
    let g = RiscvGen()
    for function in program.functions:
        g.gen_function(function)

    let h = g.to_hex()
    h.add_eof()
    h.print_hex_file()


class RiscvGen:
    var reg: int = 4
    var codes: Vector[int] = new_vector(default: 0)

    fn to_hex() -> HexFile:
        # Gather resulting binary code in a hex file.
        let h = HexFile()
        let b = ByteArray()
        for code in codes:
            b.pack_u32_le(code)
        let data = b.to_bytes()
        h.add_bytes(address: 0, data)
        return h

    fn gen_function(function: bc.Function):
        for instruction in function.instructions:
            gen_instruction(instruction)
    
    fn gen_instruction(instruction: bc.Instruction):
            case instruction:
                Nop:
                    emit(riscv.Instruction.ADDI(rd: 0, rs1: 0, imm: 0))
                Dup:
                    # Allocate new register, and move value of top of stack:
                    emit(riscv.Instruction.ADDI(rd: reg + 1, rs1: reg, imm: 0))
                    reg += 1
                Literal(literal):
                    gen_literal(literal)
                Jump(v):
                    emit(riscv.Instruction.JAL(rd: 0, imm: 0))
                JumpIf(v1, v2):
                    emit(riscv.Instruction.JAL(rd: 0, imm: 0))
                Not:
                    panic("TODO: Not")
                Neg:
                    panic("TODO: Neg")
                Binop(op):
                    gen_binop(op)
                Comparison(op):
                    panic("TODO: Comparison")
                Bitop(op):
                    gen_bitop(op)
                IntToFloat:
                    panic("TODO")
                FloatToInt:
                    panic("TODO")
                IntCast(signed, bits):
                    panic("TODO: IntCast")
                ToOpaque(t):
                    panic("TODO")
                FromOpaque(t):
                    panic("TODO")
                Call(index):
                    # panic("TODO: Call")
                    # TODO: address?
                    let lr = 2  # link register
                    emit(riscv.Instruction.JAL(rd: lr, imm: 0))
                CallIndirect(parameter_types, return_type):
                    let lr = 2  # link register
                    emit(riscv.Instruction.JALR(rd: lr, rs1: 0, imm: 0))
                Return(v):
                    emit(riscv.Instruction.JAL(rd: 0, imm: 0))
                Unreachable:
                    emit(riscv.Instruction.EBREAK())
                SetupTry(try_label, except_label):
                    panic("TODO: SetupTry")
                Raise:
                    panic("TODO: Raise")
                PopTry:
                    panic("TODO: PopTry")
                GetExceptionValue:
                    panic("TODO: GetExceptionValue")
                LocalGet(index):
                    reg += 1
                    let offset = 0
                    emit(riscv.Instruction.LW(rd: reg, rs1: 0, imm: offset))
                LocalSet(index):
                    let offset = 0
                    emit(riscv.Instruction.SW(rs1: reg, rs2: 0, imm: offset))
                    reg -= 1
                GlobalGet(index):
                    reg += 1
                    let offset = 0
                    emit(riscv.Instruction.LW(rd: reg, rs1: 0, imm: offset))
                GlobalSet(index):
                    let offset = 0
                    emit(riscv.Instruction.SW(rs1: reg, rs2: 0, imm: offset))
                    reg -= 1
                ParameterGet(index):
                    reg += 1
                    let offset = 0
                    emit(riscv.Instruction.LW(rd: reg, rs1: 0, imm: offset))
                ParameterSet(index):
                    let offset = 0
                    emit(riscv.Instruction.SW(rs1: reg, rs2: 0, imm: offset))
                    reg -= 1
                GetAttr(index, ty):
                    panic("TODO: GetAttr")
                SetAttr(index):
                    panic("TODO: SetAttr")
                GetIndex:
                    panic("TODO: GetIndex")
                SetIndex:
                    panic("TODO: SetIndex")
                LoadFunc(index):
                    panic("TODO")
                StructLiteral(struct_index):
                    panic("TODO")
                UnionLiteral(struct_index, field_index):
                    panic("TODO")
                ArrayLiteral(count):
                    panic("TODO")
                ArrayLiteral2:
                    panic("TODO")

    fn gen_literal(literal: bc.LiteralValue):
        case literal:
            Int(value):
                reg += 1
                emit(riscv.Instruction.ADDI(rd: reg, rs1: 0, imm: value))
            Float(value):
                panic("TODO: Float")
            Str(value):
                panic("TODO: Str")
            Bool(value):
                let imm = 0
                if value:
                    imm = 1
                reg += 1
                emit(riscv.Instruction.ADDI(rd: reg, rs1: 0, imm))
            Char(value):
                let imm = ord(value)
                reg += 1
                emit(riscv.Instruction.ADDI(rd: reg, rs1: 0, imm))
            Null:
                panic("TODO: Null")

    fn gen_binop(op: bc.BinaryOperator):
        reg -= 1
        case op:
            Add:
                emit(riscv.Instruction.ADD(rd: reg, rs1: reg, rs2: reg + 1))
            Sub:
                emit(riscv.Instruction.SUB(rd: reg, rs1: reg, rs2: reg + 1))
            Divide:
                panic("TODO: Divide")
            Multiply:
                panic("TODO: Multiply")

    fn gen_bitop(op: bc.BitOperator):
        reg -= 1
        case op:
            Shr:
                emit(riscv.Instruction.SRL(rd: reg, rs1: reg, rs2: reg + 1))
            Shl:
                emit(riscv.Instruction.SLL(rd: reg, rs1: reg, rs2: reg + 1))
            Xor:
                emit(riscv.Instruction.XOR(rd: reg, rs1: reg, rs2: reg + 1))
            And:
                emit(riscv.Instruction.AND(rd: reg, rs1: reg, rs2: reg + 1))
            Or:
                emit(riscv.Instruction.OR(rd: reg, rs1: reg, rs2: reg + 1))

    fn emit(instruction?: riscv.Instruction):
        let txt = riscv.instruction_to_string(instruction)
        let code = riscv.encode_instruction(instruction)
        print("--> {int_to_hex_string(code)} -> {txt} ")
        codes.append(code)

