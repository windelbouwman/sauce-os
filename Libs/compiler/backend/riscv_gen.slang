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
from std import print
import riscv
from datatypes import Option
from register_allocation import MachineInstruction, MachineBlock, MachineFunction, reg_alloc
from vectype import Vector, new_vector # , vec1
from utils import log_info, unimplemented, panic
from hashmap import HashMap, new_hashmap_str
# from strlib import int_to_hex_string
from hexfile import HexFile
from bytes import ByteArray, Bytes

pub fn gen_riscv(program: sil.Program):
    log_info("Generating riscv code")
    program.dump()
    let g = RiscvGen()
    g.gen_program(program)

    let h = g.to_hex()
    h.add_eof()
    h.print_hex_file()

pub struct Section:
    data: Bytes

pub class BinaryOutput:
    var sections: HashMap[str, ByteArray] = new_hashmap_str()
    var current_section: Option[str] = Option.None()

    fn select_section(name: str):
        if not sections.contains(key: name):
            sections.insert(key: name, value: ByteArray())
        current_section = Option.Some(name)
    
    fn write(data: Bytes):
        case current_section:
            Some(name):
                let b = sections.get(key: name)
                b.extend(data)
            None:
                panic("No output section selected")

class RiscvGen:
    var reg: int = 4
    var codes: Vector[MachineInstruction[riscv.Instruction, riscv.Relocation]] = new_vector()

    pub fn to_hex() -> HexFile:
        # Gather resulting binary code in a hex file.
        let h = HexFile()
        let b = ByteArray()
        # for code in codes:
        #     b.pack_u32_le(code)
        let data = b.to_bytes()
        h.add_bytes(address: 0, data)
        h

    pub fn gen_program(program: sil.Program):
        for function in program.functions:
            gen_function(function)

    fn gen_function(function: sil.Function):
        # Instruction selection
        let mfunc = select_function(function)

        # register allocation
        reg_alloc(mfunc)

        # Instantiate actual instructions (instructions and registers are now determined):
        print("{mfunc.name}:")
        for mblock in mfunc.blocks:
            print("{mblock.name}:")
            for minst in mblock.instructions:
                let instruction = materialize(v: minst)
                print("   {riscv.instruction_to_string(instruction)}")

    fn select_function(function: sil.Function) -> MachineFunction[riscv.Instruction, riscv.Relocation]:
        let mblocks: Vector[MachineBlock[riscv.Instruction, riscv.Relocation]] = new_vector()
        for block in function.blocks:
            codes = new_vector()
            for instruction in block.instructions:
                gen_instruction(instruction)
            mblocks.append(MachineBlock(name: block.name, instructions: codes))
        
        MachineFunction(name: function.name, blocks: mblocks)

    fn gen_instruction(instruction: sil.Instruction):
        case instruction.op:
            Nop:
                emit(riscv.Instruction.ADDI(rd: 0, rs1: 0, imm: 0))
            Jump(label):
                emit(riscv.Instruction.JAL(rd: 0, imm: 0))
            JumpNonZero(condition, label1, label2):
                emit(riscv.Instruction.JAL(rd: 0, imm: 0))
            Binop(dst, op2, lhs, rhs):
                case op2:
                    Add:
                        emit(riscv.Instruction.ADD(rd: reg, rs1: reg, rs2: reg + 1))
                    Sub:
                        emit(riscv.Instruction.SUB(rd: reg, rs1: reg, rs2: reg + 1))
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
                            emit(riscv.Instruction.ADDI(rd: 7, rs1: 8, imm: 0))
                        Global(name):
                            emit(riscv.Instruction.LA(rd: 7, offset: 0))
                    else:
                        unimplemented("arg: {sil.value_to_string(argument)}")

                # Invoke function
                case callee:
                    Global(name):
                        emit(riscv.Instruction.JAL(rd: 1, imm: 0))
                    Tmp(name):
                        emit(riscv.Instruction.JALR(rd: 1, rs1: 9, imm: 0))
                else:
                    unimplemented("Call: {sil.value_to_string(callee)}")
                
                # Eventually gather return value
                case dst:
                    Some(value):
                        pass
                    None:
                        pass
            Return(v):
                emit(riscv.Instruction.RET())
            Halt:
                emit(riscv.Instruction.EBREAK())
            Alloc(addr, size):
                # unimplemented("Alloc")
                pass
            Load(dst, addr):
                reg += 1
                let offset = 0
                emit(riscv.Instruction.LW(rd: reg, rs1: 0, imm: offset))
            Store(addr, value):
                let offset = 0
                emit(riscv.Instruction.SW(rs1: reg, rs2: 0, imm: offset))
                reg -= 1

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

    fn emit(instruction?: riscv.Instruction):
        #let code = riscv.encode_instruction(instruction)
        #print("--> {int_to_hex_string(code)} -> {txt} ")
        # let txt = riscv.instruction_to_string(instruction)
        # print("--> {txt} ")
        let uses: Vector[int] = new_vector()
        let defs: Vector[int] = new_vector()
        emit_full(instruction, uses, defs)
    
    fn emit_full(instruction?: riscv.Instruction, uses: Vector[int], defs: Vector[int]):
        let relocation: Option[riscv.Relocation] = Option.None()
        let minst = MachineInstruction(instruction, uses, defs, relocation)
        codes.append(minst)


fn materialize[R](v: MachineInstruction[riscv.Instruction, R]) -> riscv.Instruction:
    case v.instruction:
        JAL(rd, imm):
            # rd = v.defs[0]
            riscv.Instruction.JAL(rd, imm)
    else:
        v.instruction
