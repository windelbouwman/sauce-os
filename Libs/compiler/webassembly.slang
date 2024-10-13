""" 
WebAssembly
===========

WebAssembly support.

"""

from datatypes import List
from utils import panic
from std import float_to_str, print
from strlib import str_join

struct Module:
    types: List[Type]
    imports: List[Import]
    functions: List[Function]
    exports: List[Export]
    datas: List[Data]

enum ValueType:
    i32
    i64
    f32
    f64

#enum Type:
#    Value(t: ValueType)
#    Function(ref: int)

struct Type:
    params: List[ValueType]
    results: List[ValueType]

fn value_type_to_string(ty?: ValueType) -> str:
    let txt = "?"
    case ty:
        i32:
            txt = "i32"
        i64:
            txt = "i64"
        f32:
            txt = "f32"
        f64:
            txt = "f64"
    return txt

fn type_to_string(ty?: Type) -> str:
    let parts2: List[str] = List()
    let parts: List[str] = List()
    if not ty.params.is_empty():
        parts.clear()
        for param in ty.params:
            parts.append(value_type_to_string(param))
        let params_txt = str_join(parts, sep: " ")
        parts2.append("(param {params_txt})")

    if not ty.results.is_empty():
        parts.clear()
        for result in ty.results:
            parts.append(value_type_to_string(result))
        let results_txt = str_join(parts, sep: " ")
        parts2.append("(result {results_txt})")

    return str_join(parts: parts2, sep: " ") 

struct Import:
    module: str
    name: str
    ty: int  # Type ref
    # TODO: description

struct Function:
    ty: int  # reference to a type
    locals: List[ValueType]
    code: List[Instruction]

struct Export:
    name: str
    funcidx: int

struct Data:
    offset: int
    text: str

enum Instruction:

    # Control:
    ctrl_unreachable
    ctrl_nop
    ctrl_block
    ctrl_loop
    ctrl_if
    ctrl_else
    ctrl_end

    ctrl_br(labelidx: int)
    ctrl_br_if(labelidx: int)
    ctrl_br_table
    ctrl_return
    ctrl_call(funcidx: int)
    ctrl_call_indirect(tableidx: int)

    # parametric instructions

    # variable instructions
    local_get(localidx: int)
    local_set(localidx: int)
    local_tee(localidx: int)
    global_get(globalidx: int)
    global_set(globalidx: int)

    # table instructions

    # Memory instructions
    i32_load(align: int, offset: int)
    i64_load(align: int, offset: int)
    f32_load(align: int, offset: int)
    f64_load(align: int, offset: int)

    i32_store(align: int, offset: int)
    i64_store(align: int, offset: int)
    f32_store(align: int, offset: int)
    f64_store(align: int, offset: int)

    # Numeric constants
    i32_const(value: int)
    i64_const(value: int)
    f32_const(value: float)
    f64_const(value: float)

    # numeric operations
    i32_eqz
    i32_eq
    i32_ne
    i32_lt_s
    i32_lt_u
    i32_gt_s
    i32_gt_u
    i32_le_s
    i32_le_u
    i32_ge_s
    i32_ge_u

    i64_eqz
    i64_eq
    i64_ne
    i64_lt_s
    i64_lt_u
    i64_gt_s
    i64_gt_u
    i64_le_s
    i64_le_u
    i64_ge_s
    i64_ge_u

    f32_eq
    f32_ne
    f32_lt
    f32_gt
    f32_le
    f32_ge

    f64_eq
    f64_ne
    f64_lt
    f64_gt
    f64_le
    f64_ge

    i32_clz
    i32_ctz
    i32_popcnt
    i32_add
    i32_sub
    i32_mul
    i32_div_s
    i32_div_u
    i32_rem_s
    i32_rem_u
    i32_and
    i32_or
    i32_xor
    i32_shl
    i32_shr_s
    i32_shr_u
    i32_rotl
    i32_rotr

    i64_clz
    i64_ctz
    i64_popcnt
    i64_add
    i64_sub
    i64_mul
    i64_div_s
    i64_div_u
    i64_rem_s
    i64_rem_u
    i64_and
    i64_or
    i64_xor
    i64_shl
    i64_shr_s
    i64_shr_u
    i64_rotl
    i64_rotr

    f32_abs
    f32_neg
    f32_ceil
    f32_floor
    f32_trunc
    f32_nearest
    f32_sqrt
    f32_add
    f32_sub
    f32_mul
    f32_div
    f32_min
    f32_max
    f32_copysign

    f64_abs
    f64_neg
    f64_ceil
    f64_floor
    f64_trunc
    f64_nearest
    f64_sqrt
    f64_add
    f64_sub
    f64_mul
    f64_div
    f64_min
    f64_max
    f64_copysign

    i32_wrap_i64
    i32_trunc_f32_s
    i32_trunc_f32_u
    i32_trunc_f64_s
    i32_trunc_f64_u
    i64_extend_i32_s
    i64_extend_i32_u
    i64_trunc_f32_s
    i64_trunc_f32_u
    i64_trunc_f64_s
    i64_trunc_f64_u
    f32_convert_i32_s
    f32_convert_i32_u
    f32_convert_i64_s
    f32_convert_i64_u
    f32_demote_f64
    f64_convert_i32_s
    f64_convert_i32_u
    f64_convert_i64_s
    f64_convert_i64_u
    f64_promote_f32
    i32_reinterpret_f32
    i64_reinterpret_f64
    f32_reinterpret_i32
    f64_reinterpret_i64

    i32_extend8_s
    i32_extend16_s
    i64_extend8_s
    i64_extend16_s
    i64_extend32_s

fn pack_leb128(value: int):
    pass

fn pack_u32(value?: int):
    pass

fn pack_byte(opcode?: int):
    pass

fn pack_memarg(align: int, offset: int):
    pack_u32(align)
    pack_u32(offset)

fn encode(instruction: Instruction):
    case instruction:

        ctrl_unreachable:
            pack_byte(0x00)
        ctrl_nop:
            pack_byte(0x01)
        ctrl_block:
            pack_byte(0x02)
            pack_byte(0x40)  # block type = epsilon
        ctrl_loop:
            pack_byte(0x03)
            pack_byte(0x40)  # block type = epsilon
        ctrl_if:
            pack_byte(0x04)
            pack_byte(0x40)  # block type = epsilon
        ctrl_else:
            pack_byte(0x05)
        ctrl_end:
            pack_byte(0x0B)

        ctrl_br(labelidx):
            pack_byte(0x0C)
            pack_u32(labelidx)
        ctrl_br_if(labelidx):
            pack_byte(0x0D)
            pack_u32(labelidx)
        ctrl_br_table:
            pack_byte(0x0E)
        ctrl_return:
            pack_byte(0x0F)
        ctrl_call(funcidx):
            pack_byte(0x10)
            pack_u32(funcidx)
        ctrl_call_indirect(tableidx):
            pack_byte(0x11)
            pack_u32(tableidx)

        local_get(localidx):
            pack_byte(0x20)
            pack_u32(localidx)
        local_set(localidx):
            pack_byte(0x21)
            pack_u32(localidx)
        local_tee(localidx):
            pack_byte(0x22)
            pack_u32(localidx)
        global_get(globalidx):
            pack_byte(0x23)
            pack_u32(globalidx)
        global_set(globalidx):
            pack_byte(0x24)
            pack_u32(globalidx)

        i32_load(align, offset):
            pack_byte(0x28)
            pack_memarg(align, offset)
        i64_load(align, offset):
            pack_byte(0x29)
            pack_memarg(align, offset)
        f32_load(align, offset):
            pack_byte(0x2A)
            pack_memarg(align, offset)
        f64_load(align, offset):
            pack_byte(0x2B)
            pack_memarg(align, offset)

        i32_store(align, offset):
            pack_byte(0x36)
            pack_memarg(align, offset)
        i64_store(align, offset):
            pack_byte(0x37)
            pack_memarg(align, offset)
        f32_store(align, offset):
            pack_byte(0x38)
            pack_memarg(align, offset)
        f64_store(align, offset):
            pack_byte(0x39)
            pack_memarg(align, offset)

        i32_const(value):
            pack_byte(0x41)
        i64_const(value):
            pack_byte(0x42)
        f32_const(value):
            pack_byte(0x43)
        f64_const(value):
            pack_byte(0x44)

        i32_eqz:
            pack_byte(0x45)
        i32_eq:
            pack_byte(0x46)
        i32_ne:
            pack_byte(0x47)
        i32_lt_s:
            pack_byte(0x48)
        i32_lt_u:
            pack_byte(0x49)
        i32_gt_s:
            pack_byte(0x4A)
        i32_gt_u:
            pack_byte(0x4B)
        i32_le_s:
            pack_byte(0x4C)
        i32_le_u:
            pack_byte(0x4D)
        i32_ge_s:
            pack_byte(0x4E)
        i32_ge_u:
            pack_byte(0x4F)

        i64_eqz:
            pack_byte(0x50)
        i64_eq:
            pack_byte(0x51)
        i64_ne:
            pack_byte(0x52)
        i64_lt_s:
            pack_byte(0x53)
        i64_lt_u:
            pack_byte(0x54)
        i64_gt_s:
            pack_byte(0x55)
        i64_gt_u:
            pack_byte(0x56)
        i64_le_s:
            pack_byte(0x57)
        i64_le_u:
            pack_byte(0x58)
        i64_ge_s:
            pack_byte(0x59)
        i64_ge_u:
            pack_byte(0x5A)

        f32_eq:
            pack_byte(0x5B)
        f32_ne:
            pack_byte(0x5C)
        f32_lt:
            pack_byte(0x5D)
        f32_gt:
            pack_byte(0x5E)
        f32_le:
            pack_byte(0x5F)
        f32_ge:
            pack_byte(0x60)

        f64_eq:
            pack_byte(0x61)
        f64_ne:
            pack_byte(0x62)
        f64_lt:
            pack_byte(0x63)
        f64_gt:
            pack_byte(0x64)
        f64_le:
            pack_byte(0x65)
        f64_ge:
            pack_byte(0x66)

        i32_clz:
            pack_byte(0x67)
        i32_ctz:
            pack_byte(0x68)
        i32_popcnt:
            pack_byte(0x69)
        i32_add:
            pack_byte(0x6A)
        i32_sub:
            pack_byte(0x6B)
        i32_mul:
            pack_byte(0x6C)
        i32_div_s:
            pack_byte(0x6D)
        i32_div_u:
            pack_byte(0x6E)
        i32_rem_s:
            pack_byte(0x6F)
        i32_rem_u:
            pack_byte(0x70)
        i32_and:
            pack_byte(0x71)
        i32_or:
            pack_byte(0x72)
        i32_xor:
            pack_byte(0x73)
        i32_shl:
            pack_byte(0x74)
        i32_shr_s:
            pack_byte(0x75)
        i32_shr_u:
            pack_byte(0x76)
        i32_rotl:
            pack_byte(0x77)
        i32_rotr:
            pack_byte(0x78)

        i64_clz:
            pack_byte(0x79)
        i64_ctz:
            pack_byte(0x7A)
        i64_popcnt:
            pack_byte(0x7B)
        i64_add:
            pack_byte(0x7C)
        i64_sub:
            pack_byte(0x7D)
        i64_mul:
            pack_byte(0x7E)
        i64_div_s:
            pack_byte(0x7F)
        i64_div_u:
            pack_byte(0x80)
        i64_rem_s:
            pack_byte(0x81)
        i64_rem_u:
            pack_byte(0x82)
        i64_and:
            pack_byte(0x83)
        i64_or:
            pack_byte(0x84)
        i64_xor:
            pack_byte(0x85)
        i64_shl:
            pack_byte(0x86)
        i64_shr_s:
            pack_byte(0x87)
        i64_shr_u:
            pack_byte(0x88)
        i64_rotl:
            pack_byte(0x89)
        i64_rotr:
            pack_byte(0x8A)

        f32_abs:
            pack_byte(0x8B)
        f32_neg:
            pack_byte(0x8C)
        f32_ceil:
            pack_byte(0x8D)
        f32_floor:
            pack_byte(0x8E)
        f32_trunc:
            pack_byte(0x8F)
        f32_nearest:
            pack_byte(0x90)
        f32_sqrt:
            pack_byte(0x91)
        f32_add:
            pack_byte(0x92)
        f32_sub:
            pack_byte(0x93)
        f32_mul:
            pack_byte(0x94)
        f32_div:
            pack_byte(0x95)
        f32_min:
            pack_byte(0x96)
        f32_max:
            pack_byte(0x97)
        f32_copysign:
            pack_byte(0x98)

        f64_abs:
            pack_byte(0x99)
        f64_neg:
            pack_byte(0x9A)
        f64_ceil:
            pack_byte(0x9B)
        f64_floor:
            pack_byte(0x9C)
        f64_trunc:
            pack_byte(0x9D)
        f64_nearest:
            pack_byte(0x9E)
        f64_sqrt:
            pack_byte(0x9F)
        f64_add:
            pack_byte(0xA0)
        f64_sub:
            pack_byte(0xA1)
        f64_mul:
            pack_byte(0xA2)
        f64_div:
            pack_byte(0xA3)
        f64_min:
            pack_byte(0xA4)
        f64_max:
            pack_byte(0xA5)
        f64_copysign:
            pack_byte(0xA6)

        i32_wrap_i64:
            pack_byte(0xA7)
        i32_trunc_f32_s:
            pack_byte(0xA8)
        i32_trunc_f32_u:
            pack_byte(0xA9)
        i32_trunc_f64_s:
            pack_byte(0xAA)
        i32_trunc_f64_u:
            pack_byte(0xAB)
        i64_extend_i32_s:
            pack_byte(0xAC)
        i64_extend_i32_u:
            pack_byte(0xAD)
        i64_trunc_f32_s:
            pack_byte(0xAE)
        i64_trunc_f32_u:
            pack_byte(0xAF)
        i64_trunc_f64_s:
            pack_byte(0xB0)
        i64_trunc_f64_u:
            pack_byte(0xB1)
        f32_convert_i32_s:
            pack_byte(0xB2)
        f32_convert_i32_u:
            pack_byte(0xB3)
        f32_convert_i64_s:
            pack_byte(0xB4)
        f32_convert_i64_u:
            pack_byte(0xB5)
        f32_demote_f64:
            pack_byte(0xB6)
        f64_convert_i32_s:
            pack_byte(0xB7)
        f64_convert_i32_u:
            pack_byte(0xB8)
        f64_convert_i64_s:
            pack_byte(0xB9)
        f64_convert_i64_u:
            pack_byte(0xBA)
        f64_promote_f32:
            pack_byte(0xBB)
        i32_reinterpret_f32:
            pack_byte(0xBC)
        i64_reinterpret_f64:
            pack_byte(0xBD)
        f32_reinterpret_i32:
            pack_byte(0xBE)
        f64_reinterpret_i64:
            pack_byte(0xBF)

        i32_extend8_s:
            pack_byte(0xC0)
        i32_extend16_s:
            pack_byte(0xC1)
        i64_extend8_s:
            pack_byte(0xC2)
        i64_extend16_s:
            pack_byte(0xC3)
        i64_extend32_s:
            pack_byte(0xC4)

fn to_string(instruction: Instruction) -> str:
    let txt = ""

    case instruction:
        ctrl_unreachable:
            txt = "unreachable"
        ctrl_nop:
            txt = "nop"
        ctrl_block:
            txt = "block"
        ctrl_loop:
            txt = "loop"
        ctrl_if:
            txt = "if"
        ctrl_else:
            txt = "else"
        ctrl_end:
            txt = "end"

        ctrl_br(labelidx):
            txt = "br {labelidx}"
        ctrl_br_if(labelidx):
            txt = "br_if {labelidx}"
        ctrl_br_table:
            txt = "br_table"
        ctrl_return:
            txt = "return"
        ctrl_call(funcidx):
            txt = "call {funcidx}"
        ctrl_call_indirect(tableidx):
            txt = "call_indirect {tableidx}"

        local_get(localidx):
            txt = "local.get {localidx}"
        local_set(localidx):
            txt = "local.set {localidx}"
        local_tee(localidx):
            txt = "local.tee {localidx}"
        global_get(globalidx):
            txt = "global.get {globalidx}"
        global_set(globalidx):
            txt = "global.set {globalidx}"


        i32_load(align, offset):
            txt = "i32.load offset={offset} align={align}"

        i64_load(align, offset):
            txt = "i64.load offset={offset} align={align}"

        f32_load(align, offset):
            txt = "f32.load offset={offset} align={align}"

        f64_load(align, offset):
            txt = "f64.load offset={offset} align={align}"

        i32_store(align, offset):
            txt = "i32.store offset={offset} align={align}"

        i64_store(align, offset):
            txt = "i64.store offset={offset} align={align}"

        f32_store(align, offset):
            txt = "f32.store offset={offset} align={align}"

        f64_store(align, offset):
            txt = "f64.store offset={offset} align={align}"

        i32_const(value):
            txt = "i32.const {value}"
        i64_const(value):
            txt = "i64.const {value}"
        f32_const(value):
            txt = "f32.const {float_to_str(value)}"
        f64_const(value):
            txt = "f64.const {float_to_str(value)}"

        i32_eqz:
            txt = "i32.eqz"
        i32_eq:
            txt = "i32.eq"
        i32_ne:
            txt = "i32.ne"
        i32_lt_s:
            txt = "i32.lt_s"
        i32_lt_u:
            txt = "i32.lt_u"
        i32_gt_s:
            txt = "i32.gt_s"
        i32_gt_u:
            txt = "i32.gt_u"
        i32_le_s:
            txt = "i32.le_s"
        i32_le_u:
            txt = "i32.le_u"
        i32_ge_s:
            txt = "i32.ge_s"
        i32_ge_u:
            txt = "i32.ge_u"
             

        i64_eqz:
            txt = "i64.eqz"
        i64_eq:
            txt = "i64.eq"
        i64_ne:
            txt = "i64.ne"
        i64_lt_s:
            txt = "i64.lt_s"
        i64_lt_u:
            txt = "i64.lt_u"
        i64_gt_s:
            txt = "i64.gt_s"
        i64_gt_u:
            txt = "i64.gt_u"
        i64_le_s:
            txt = "i64.le_s"
        i64_le_u:
            txt = "i64.le_u"
        i64_ge_s:
            txt = "i64.ge_s"
        i64_ge_u:
            txt = "i64.ge_u"

        f32_eq:
            txt = "f32.eq"
        f32_ne:
            txt = "f32.ne"
        f32_lt:
            txt = "f32.lt"
        f32_gt:
            txt = "f32.gt"
        f32_le:
            txt = "f32.le"
        f32_ge:
            txt = "f32.ge"

        f64_eq:
            txt = "f64.eq"
        f64_ne:
            txt = "f64.ne"
        f64_lt:
            txt = "f64.lt"
        f64_gt:
            txt = "f64.gt"
        f64_le:
            txt = "f64.le"
        f64_ge:
            txt = "f64.ge"

        i32_clz:
            txt = "i32.clz"
        i32_ctz:
            txt = "i32.ctz"
        i32_popcnt:
            txt = "i32.popcnt"
        i32_add:
            txt = "i32.add"
        i32_sub:
            txt = "i32.sub"
        i32_mul:
            txt = "i32.mul"
        i32_div_s:
            txt = "i32.div_s"
        i32_div_u:
            txt = "i32.div_u"
        i32_rem_s:
            txt = "i32.rem_s"
        i32_rem_u:
            txt = "i32.rem_u"
        i32_and:
            txt = "i32.and"
        i32_or:
            txt = "i32.or"
        i32_xor:
            txt = "i32.xor"
        i32_shl:
            txt = "i32.shl"
        i32_shr_s:
            txt = "i32.shr_s"
        i32_shr_u:
            txt = "i32.shr_u"
        i32_rotl:
            txt = "i32.rotl"
        i32_rotr:
            txt = "i32.rotr"
            

        i64_clz:
            txt = "i64.clz"
        i64_ctz:
            txt = "i64.ctz"
        i64_popcnt:
            txt = "i64.popcnt"
        i64_add:
            txt = "i64.add"
        i64_sub:
            txt = "i64.sub"
        i64_mul:
            txt = "i64.mul"
        i64_div_s:
            txt = "i64.div_s"
        i64_div_u:
            txt = "i64.div_u"
        i64_rem_s:
            txt = "i64.rem_s"
        i64_rem_u:
            txt = "i64.rem_u"
        i64_and:
            txt = "i64.and"
        i64_or:
            txt = "i64.or"
        i64_xor:
            txt = "i64.xor"
        i64_shl:
            txt = "i64.shl"
        i64_shr_s:
            txt = "i64.shr_s"
        i64_shr_u:
            txt = "i64.shr_u"
        i64_rotl:
            txt = "i64.rotl"
        i64_rotr:
            txt = "i64.rotr"

        f32_abs:
            txt = "f32.abs"
        f32_neg:
            txt = "f32.neg"
        f32_ceil:
            txt = "f32.ceil"
        f32_floor:
            txt = "f32.floor"
        f32_trunc:
            txt = "f32.trunc"
        f32_nearest:
            txt = "f32.nearest"
        f32_sqrt:
            txt = "f32.sqrt"
        f32_add:
            txt = "f32.add"
        f32_sub:
            txt = "f32.sub"
        f32_mul:
            txt = "f32.mul"
        f32_div:
            txt = "f32.div"
        f32_min:
            txt = "f32.min"
        f32_max:
            txt = "f32.max"
        f32_copysign:
            txt = "f32.copysign"

        f64_abs:
            txt = "f64.abs"
        f64_neg:
            txt = "f64.neg"
        f64_ceil:
            txt = "f64.ceil"
        f64_floor:
            txt = "f64.floor"
        f64_trunc:
            txt = "f64.trunc"
        f64_nearest:
            txt = "f64.nearest"
        f64_sqrt:
            txt = "f64.sqrt"
        f64_add:
            txt = "f64.add"
        f64_sub:
            txt = "f64.sub"
        f64_mul:
            txt = "f64.mul"
        f64_div:
            txt = "f64.div"
        f64_min:
            txt = "f64.min"
        f64_max:
            txt = "f64.max"
        f64_copysign:
            txt = "f64.copysign"

        i32_wrap_i64:
            txt = "i32.wrap_i64"
        i32_trunc_f32_s:
            txt = "i32.trunc_f32_s"
        i32_trunc_f32_u:
            txt = "i32.trunc_f32_u"
        i32_trunc_f64_s:
            txt = "i32.trunc_f64_s"
        i32_trunc_f64_u:
            txt = "i32.trunc_f64_u"
        i64_extend_i32_s:
            txt = "i64.extend_i32_s"
        i64_extend_i32_u:
            txt = "i64.extend_i32_u"
        i64_trunc_f32_s:
            txt = "i64.trunc_f32_s"
        i64_trunc_f32_u:
            txt = "i64.trunc_f32_u"
        i64_trunc_f64_s:
            txt = "i64.trunc_f64_s"
        i64_trunc_f64_u:
            txt = "i64.trunc_f64_u"
        f32_convert_i32_s:
            txt = "f32.convert_i32_s"
        f32_convert_i32_u:
            txt = "f32.convert_i32_u"
        f32_convert_i64_s:
            txt = "f32.convert_i64_s"
        f32_convert_i64_u:
            txt = "f32.convert_i64_u"
        f32_demote_f64:
            txt = "f32.demote_f64"
        f64_convert_i32_s:
            txt = "f64.convert_i32_s"
        f64_convert_i32_u:
            txt = "f64.convert_i32_u"
        f64_convert_i64_s:
            txt = "f64.convert_i64_s"
        f64_convert_i64_u:
            txt = "f64.convert_i64_u"
        f64_promote_f32:
            txt = "f64.promote_f32"
        i32_reinterpret_f32:
            txt = "i32.reinterpret_f32"
        i64_reinterpret_f64:
            txt = "i64.reinterpret_f64"
        f32_reinterpret_i32:
            txt = "f32.reinterpret_i32"
        f64_reinterpret_i64:
            txt = "f64.reinterpret_i64"

        i32_extend8_s:
            txt = "i32.extend8_s"
        i32_extend16_s:
            txt = "i32.extend16_s"
        i64_extend8_s:
            txt = "i64.extend8_s"
        i64_extend16_s:
            txt = "i64.extend16_s"
        i64_extend32_s:
            txt = "i64.extend32_s"

    return txt


fn to_wat(module: Module):
    # Print webassembly module in text format (WAT)

    print("(module")
    for ty in module.types:
        let type_txt = type_to_string(ty)
        print("  (type (func {type_txt}))")

    for imp in module.imports:
        print("  (import \"{imp.module}\" \"{imp.name}\" (func (type {imp.ty})))")
    
    print("  (import \"js\" \"mem\" (memory 25))")

    for function in module.functions:
        print("  (func (type {function.ty})")
        for local in function.locals:
            print("    (local {value_type_to_string(ty: local)})")

        for instruction in function.code:
            print("    {to_string(instruction)}")
        print("  )")

    # print("  (memory 25)")

    for ex in module.exports:
        print("  (export \"{ex.name}\" (func {ex.funcidx}))")

    for data in module.datas:
        print("  (data (i32.const {data.offset}) \"{data.text}\")")

    print(")")
