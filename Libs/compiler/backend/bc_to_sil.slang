""" Transform BC into SIL

Features of this pass:

- Compile structured types into pointers with load/store operations
- Implement multiply and divide by either physical instructions or a function call to a library

"""

from datatypes import List, Option
from bytes import Bytes, bytes_from_ascii
from utils import log_info, panic, unimplemented
import bc
import sil

pub struct SilGenOptions:
    """ Target specific options """
    has_div: bool
    has_mul: bool
    has_fpu: bool
    word_size: int

pub fn to_sil(program: bc.Program) -> sil.Program:
    # TODO: pass options, su
    log_info("Creating SIL program from bytecode")
    let g = SilGen(m_bc_program: program)
    g.gen_program()

class SilGen:
    var m_bc_program: bc.Program
    var m_functions: List[sil.Function] = List()
    var m_blobs: List[sil.DataBlob] = List()
    var m_blocks: List[sil.Block] = List()
    var m_current_block: Option[sil.Block] = Option.None()
    var m_block_is_terminated: bool = false
    var m_locals: List[sil.Value] = List()
    var m_tmp_number: int = 0
    var m_value_stack: List[sil.Value] = List()

    pub fn gen_program() -> sil.Program:
        for function in m_bc_program.functions:
            gen_function(function)
        sil.Program(functions: m_functions, blobs: m_blobs)

    fn gen_function(function: bc.Function):
        log_info("Gen code for function {function.name}")
        m_blocks = List()
        m_value_stack = List()
        let start = new_block(name: "start")
        set_current_block(start)

        for n in function.locals:
            let addr = new_tmp()
            let size = 8 # TODO
            emit(op: sil.OpCode.Alloc(addr, size))
            m_locals.append(addr)

        let target_indici = bc.get_target_labels(instructions: function.instructions)
        let index = 0
        for opcode in function.instructions:
            if target_indici.contains(index):
                let name = "b_{index}"
                if not m_block_is_terminated:
                    emit(sil.OpCode.Jump(name))
                set_current_block(new_block(name))
            gen_opcode(opcode)
            index += 1
        
        let sil_function = sil.Function(name: function.name, start, blocks: m_blocks)
        m_functions.append(sil_function)

    fn gen_opcode(opcode: bc.Instruction):
        # log_info("Gen {bc.instruction_to_string(opcode)}")
        case opcode:
            Nop:
                pass
            Literal(literal):
                case literal:
                    Int(value):
                        push_int(value)
                    Float(value):
                        push_int(99999) # TODO
                    Str(value):
                        # emit(op: sil.OpCode.Nop())
                        let data = bytes_from_ascii(text: value)
                        let literal_label = add_data_blob(data)
                        push(literal_label)
                    Bool(value):
                        if value:
                            push_int(1)
                        else:
                            push_int(0)
                else:
                    unimplemented(bc.literal_to_string(literal))
            Binop(op):
                let rhs = pop()
                let lhs = pop()
                let op2 = sil.BinaryOp.Add()
                case op:
                    Add:
                        op2 = sil.BinaryOp.Add()
                    Sub:
                        op2 = sil.BinaryOp.Sub()
                    Divide:
                        op2 = sil.BinaryOp.Div()
                    Multiply:
                        op2 = sil.BinaryOp.Mul()
                let dst = new_tmp()
                push(dst)
                emit(sil.OpCode.Binop(dst, op2, lhs, rhs))
            Comparison(op):
                let rhs = pop()
                let lhs = pop()
                let dst = new_tmp()
                push(dst)
                let op2 = sil.CompOp.Eq()
                case op:
                    Greater:
                        op2 = sil.CompOp.Gt()
                    Less:
                        op2 = sil.CompOp.Lt()
                    GreaterEquals:
                        op2 = sil.CompOp.Gte()
                    LessEquals:
                        op2 = sil.CompOp.Lte()
                    Equals:
                        op2 = sil.CompOp.Eq()
                    NotEquals:
                        op2 = sil.CompOp.Neq()
                emit(sil.OpCode.Compare(dst, op2, lhs, rhs))
            LocalGet(index):
                let addr = m_locals[index]
                let value = new_tmp()
                emit(sil.OpCode.Load(dst: value, addr))
                push(value)
            LocalSet(index):
                let addr = m_locals[index]
                let value = pop()
                emit(sil.OpCode.Store(addr, value))
            JumpIf(label1, label2):
                let condition = pop()
                emit(sil.OpCode.JumpNonZero(condition, label1: "x_{label1}", label2: "x_{label2}"))
            Jump(label):
                emit(sil.OpCode.Jump(label: "x_{label}"))
            Call(index):
                let n = 2
                if index < m_bc_program.extern_functions.len():
                    let function = m_bc_program.extern_functions[index]
                    let callee = new_global(function.name)
                    gen_call(callee, n_args: function.parameters.len(), return_type: function.return_type)
                else:
                    index = index - m_bc_program.extern_functions.len()
                    let function = m_bc_program.functions[index]
                    let callee = new_global(function.name)
                    gen_call(callee, n_args: function.parameters.len(), return_type: function.return_type)
                
            Return(v):
                emit(sil.OpCode.Return(value: Option.None()))
            Unreachable:
                emit(sil.OpCode.Halt())
        else:
            unimplemented(bc.instruction_to_string(opcode))
    
    fn gen_call(callee: sil.Value, n_args: int, return_type: Option[bc.Type]):
        let arguments = pop_n(count: n_args)
        case return_type:
            Some(ty):
                let value = new_tmp()
                emit(sil.OpCode.Call(Option.Some(value), callee, arguments))
                push(value)
            None:
                emit(sil.OpCode.Call(Option.None(), callee, arguments))

    fn new_block(name: str) -> sil.Block:
        let block = sil.Block(name, instructions: List())
        m_blocks.append(block)
        block
    
    fn new_tmp() -> sil.Value:
        sil.Value.Tmp(name: "x{new_id()}")
    
    fn new_id() -> int:
        m_tmp_number += 1
        m_tmp_number
    
    fn new_global(name?: str) -> sil.Value:
        sil.Value.Global(name)
    
    fn add_data_blob(data?: Bytes) -> sil.Value:
        # TODO: we have a chance to deduplicate blobs here!
        let name = "lit_{new_id()}"
        m_blobs.append(sil.DataBlob(name, data))
        sil.Value.Global(name)
    
    fn push_int(value?: int):
        push(sil.Value.Integer(value))
    
    fn push(value?: sil.Value):
        m_value_stack.append(value)

    fn pop() -> sil.Value:
        m_value_stack.pop_last()

    fn pop_n(count: int) -> List[sil.Value]:
        let values: List[sil.Value] = List()
        while count > 0:
            let val = pop()
            values.prepend(val)
            count -= 1
        values

    fn set_current_block(block?: sil.Block):
        m_current_block = Option.Some(block)
        m_block_is_terminated = false

    fn emit(op?: sil.OpCode):
        case m_current_block:
            Some(block):
                if m_block_is_terminated:
                    panic("Block already terminated!")
                else:
                    case op:
                        Jump(label):
                            m_block_is_terminated = true
                        JumpNonZero(c, label1, label2):
                            m_block_is_terminated = true
                        Return(value):
                            m_block_is_terminated = true
                        Halt:
                            m_block_is_terminated = true
                    else:
                        pass
                let instruction = sil.Instruction(op)
                block.instructions.append(instruction)
            None:
                panic("Cannot emit")
