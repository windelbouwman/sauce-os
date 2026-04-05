module compiler.webassembly
"""WebAssembly
===========

WebAssembly support.
"""

from base.listtype import List, list1
from std import float_to_str2, str_len
from base.bytes import Bytes, ByteArray, bytes_from_ascii
from base.leb128 import pack_unsigned_leb128, pack_signed_leb128
from text_gen import TextGenerator
from base.utils import panic
from base.strlib import str_join, hex_char

pub struct Module:
	types: List[CompType]
	imports: List[Import]
	tags: List[Tag]
	globals: List[Global]
	functions: List[Function]
	exports: List[Export]
	datas: List[Data]

pub enum NumType:
	i32
	i64
	f32
	f64

pub struct BlockType:
	params: List[ValueType]
	results: List[ValueType]

pub fn one_result_block_type(result_type?: ValueType) -> BlockType:
	BlockType(params: List(), results: list1(result_type))

pub fn empty_block_type() -> BlockType:
	BlockType(params: List(), results: List())

pub enum ValueType:
	Num(ty: NumType)
	Ref(ty: RefType)

pub fn nullable_ref_type(heap_type?: HeapType) -> RefType:
	RefType(nullable: true, heap_type)

pub fn ref_type(heap_type?: HeapType) -> RefType:
	RefType(nullable: false, heap_type)

pub fn ref_extern_type() -> RefType:
	RefType(nullable: false, heap_type: HeapType.Extern())

pub struct RefType:
	nullable: bool
	heap_type: HeapType

pub enum HeapType:
	Any
	i31
	Func
	Extern
	TypeIdx(index: int)

pub enum CompType:
	Struct(fields: List[FieldType])
	Array(ty: FieldType)
	Func(params: List[ValueType], results: List[ValueType])

pub struct FieldType:
	mutable: bool
	ty: StorageType

pub enum StorageType:
	Value(ty: ValueType)
	Packed(ty: PackType)

pub enum PackType:
	i8
	i16

fn value_type_to_string(ty?: ValueType) -> str:
	case ty:
		Num(ty): num_type_to_string(ty)
		Ref(ty): ref_type_to_string(ty)

fn num_type_to_string(ty?: NumType) -> str:
	case ty:
		i32: "i32"
		i64: "i64"
		f32: "f32"
		f64: "f64"

fn ref_type_to_string(ty?: RefType) -> str:
	let null_text = " null" if ty.nullable else ""
	"(ref{null_text} {heap_type_to_string(ty.heap_type)})"

fn heap_type_to_string(heap_type?: HeapType) -> str:
	case heap_type:
		Any: "any"
		i31: "i31"
		Func: "func"
		Extern: "extern"
		TypeIdx(index): str(index)

fn fuu(label: str, items: List[ValueType], parts2: List[str]):
	let parts: List[str] = List()
	if not items.is_empty():
		parts.clear()
		for item in items:
			parts.append(value_type_to_string(item))
		let params_txt = str_join(parts, sep: " ")
		parts2.append("({label} {params_txt})")

pub fn comp_type_to_string(comp_type?: CompType) -> str:
	case comp_type:
		Struct(field_types):
			let parts: List[str] = List()
			for field_type in field_types:
				let type_text = field_type_to_string(field_type)
				parts.append("(field (mut {type_text}))")
			let fields_txt = str_join(parts, sep: " ")
			"(struct {fields_txt})"
		Array(field_type):
			let txt = field_type_to_string(field_type)
			"(array (mut {txt}))"
		Func(params, results):
			let parts2: List[str] = List()
			fuu(label: "param", items: params, parts2)
			fuu(label: "result", items: results, parts2)
			let in_out = str_join(parts: parts2, sep: " ")
			"(func {in_out})"

fn field_type_to_string(field_type: FieldType) -> str:
	case field_type.ty:
		Value(value_type): value_type_to_string(value_type)
		Packed(packed_type): packed_type_to_string(packed_type)

fn packed_type_to_string(ty?: PackType) -> str:
	case ty:
		i8: "i8"
		i16: "i16"

pub struct Tag:
	typeidx: int

pub struct Import:
	modname: str
	name: str
	kind: ExternType
	# ty: int  # Type ref
	# TODO: description

pub enum ExternType:
	Func(typeidx: int)
	Global(ty: ValueType, mutable: bool)
	Tag(typeidx: int)

pub struct Global:
	mutable: bool
	ty: ValueType
	value: List[Instruction]

pub struct Function:
	typeidx: int  # reference to a type
	locals: List[ValueType]
	code: List[Instruction]

pub struct Export:
	name: str
	kind: ExportKind

pub enum ExportKind:
	Func(funcidx: int)
	Global(globalidx: int)
	Tag(tagidx: int)
	Memory(memidx: int)
	Table(tableidx: int)

pub struct Data:
	data: Bytes

pub enum CatchItem:
	Catch(tagindex: int, label: int)

pub enum Instruction:

	# Control:
	ctrl_unreachable
	ctrl_nop
	drop
	ctrl_block(block_type: BlockType)
	ctrl_loop(block_type: BlockType)
	ctrl_if(block_type: BlockType)
	ctrl_else
	ctrl_end

	ctrl_br(labelidx: int)
	ctrl_br_if(labelidx: int)
	ctrl_br_table
	ctrl_return
	ctrl_call(funcidx: int)
	ctrl_call_ref(ty: int)
	ctrl_call_indirect(tableidx: int)
	ctrl_throw(index: int)
	ctrl_try_table(block_type: BlockType, catches: List[CatchItem])

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
	f32_const(value: float32)
	f64_const(value: float64)

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

	# Reference instructions
	ref_func(funcidx: int)
	ref_null(ty: HeapType)
	ref_is_null
	ref_as_non_null
	ref_eq
	ref_cast(ty: RefType)
	struct_new(ty: int)
	struct_get(ty: int, field: int)
	struct_set(ty: int, field: int)
	array_new_fixed(ty: int, size: int)
	array_new_data(ty: int, dataidx: int)
	array_new_elem(ty: int, elemidx: int)
	array_new_default(ty: int)
	array_get(ty: int)
	array_set(ty: int)
	ref_i31
	i31_get(signed: bool)
	extern_convert_any
	any_convert_extern

class Writer:
	var m_buffer: ByteArray = ByteArray()

	pub fn write_u32(value?: int):
		pack_unsigned_leb128(out: m_buffer, value)

	pub fn write_s32(value?: int):
		pack_signed_leb128(out: m_buffer, value)

	pub fn write_f32(value?: float32):
		m_buffer.pack_f32_le(value)

	pub fn write_f64(value?: float64):
		m_buffer.pack_f64_le(value)

	pub fn write_byte(b?: int):
		m_buffer.append(b)

	pub fn write_data(data?: Bytes):
		m_buffer.extend(data)

	pub fn pack_memarg(align: int, offset: int):
		write_u32(align)
		write_u32(offset)

	pub fn get_bytes() -> Bytes:
		m_buffer.to_bytes()

pub fn pack_block_type(writer: Writer, block_type: BlockType):
	if block_type.results.is_empty():
		writer.write_byte(0x40)  # block type = epsilon
	elif block_type.results.len() == 1:
		pack_value_type(writer, block_type.results.get(index: 0))
	else:
		panic("Unsupported")

pub fn encode(writer: Writer, instruction: Instruction):
	case instruction:
		ctrl_unreachable:
			writer.write_byte(0x00)
		ctrl_nop:
			writer.write_byte(0x01)
		drop:
			writer.write_byte(0x1A)
		ctrl_block(block_type):
			writer.write_byte(0x02)
			pack_block_type(writer, block_type)
		ctrl_loop(block_type):
			writer.write_byte(0x03)
			pack_block_type(writer, block_type)
		ctrl_if(block_type):
			writer.write_byte(0x04)
			pack_block_type(writer, block_type)
		ctrl_else:
			writer.write_byte(0x05)
		ctrl_end:
			writer.write_byte(0x0B)

		ctrl_br(labelidx):
			writer.write_byte(0x0C)
			writer.write_u32(labelidx)
		ctrl_br_if(labelidx):
			writer.write_byte(0x0D)
			writer.write_u32(labelidx)
		ctrl_br_table:
			writer.write_byte(0x0E)
		ctrl_return:
			writer.write_byte(0x0F)
		ctrl_call(funcidx):
			writer.write_byte(0x10)
			writer.write_u32(funcidx)
		ctrl_call_ref(ty):
			writer.write_byte(0x14)
			writer.write_u32(ty)
		ctrl_call_indirect(tableidx):
			writer.write_byte(0x11)
			writer.write_u32(tableidx)
		ctrl_throw(index):
			writer.write_byte(0x08)
			writer.write_u32(index)
		ctrl_try_table(block_type, catches):
			writer.write_byte(0x1F)
			pack_block_type(writer, block_type)
			writer.write_u32(catches.len())
			for catch in catches:
				case catch:
					Catch(tagindex, label):
						writer.write_byte(0x0)
						writer.write_u32(tagindex)
						writer.write_u32(label)

		local_get(localidx):
			writer.write_byte(0x20)
			writer.write_u32(localidx)
		local_set(localidx):
			writer.write_byte(0x21)
			writer.write_u32(localidx)
		local_tee(localidx):
			writer.write_byte(0x22)
			writer.write_u32(localidx)
		global_get(globalidx):
			writer.write_byte(0x23)
			writer.write_u32(globalidx)
		global_set(globalidx):
			writer.write_byte(0x24)
			writer.write_u32(globalidx)

		i32_load(align, offset):
			writer.write_byte(0x28)
			writer.pack_memarg(align, offset)
		i64_load(align, offset):
			writer.write_byte(0x29)
			writer.pack_memarg(align, offset)
		f32_load(align, offset):
			writer.write_byte(0x2A)
			writer.pack_memarg(align, offset)
		f64_load(align, offset):
			writer.write_byte(0x2B)
			writer.pack_memarg(align, offset)

		i32_store(align, offset):
			writer.write_byte(0x36)
			writer.pack_memarg(align, offset)
		i64_store(align, offset):
			writer.write_byte(0x37)
			writer.pack_memarg(align, offset)
		f32_store(align, offset):
			writer.write_byte(0x38)
			writer.pack_memarg(align, offset)
		f64_store(align, offset):
			writer.write_byte(0x39)
			writer.pack_memarg(align, offset)

		i32_const(value):
			writer.write_byte(0x41)
			writer.write_s32(value)
		i64_const(value):
			writer.write_byte(0x42)
			writer.write_s32(value)
		f32_const(value):
			writer.write_byte(0x43)
			writer.write_f32(value)
		f64_const(value):
			writer.write_byte(0x44)
			writer.write_f64(value)

		i32_eqz:
			writer.write_byte(0x45)
		i32_eq:
			writer.write_byte(0x46)
		i32_ne:
			writer.write_byte(0x47)
		i32_lt_s:
			writer.write_byte(0x48)
		i32_lt_u:
			writer.write_byte(0x49)
		i32_gt_s:
			writer.write_byte(0x4A)
		i32_gt_u:
			writer.write_byte(0x4B)
		i32_le_s:
			writer.write_byte(0x4C)
		i32_le_u:
			writer.write_byte(0x4D)
		i32_ge_s:
			writer.write_byte(0x4E)
		i32_ge_u:
			writer.write_byte(0x4F)

		i64_eqz:
			writer.write_byte(0x50)
		i64_eq:
			writer.write_byte(0x51)
		i64_ne:
			writer.write_byte(0x52)
		i64_lt_s:
			writer.write_byte(0x53)
		i64_lt_u:
			writer.write_byte(0x54)
		i64_gt_s:
			writer.write_byte(0x55)
		i64_gt_u:
			writer.write_byte(0x56)
		i64_le_s:
			writer.write_byte(0x57)
		i64_le_u:
			writer.write_byte(0x58)
		i64_ge_s:
			writer.write_byte(0x59)
		i64_ge_u:
			writer.write_byte(0x5A)

		f32_eq:
			writer.write_byte(0x5B)
		f32_ne:
			writer.write_byte(0x5C)
		f32_lt:
			writer.write_byte(0x5D)
		f32_gt:
			writer.write_byte(0x5E)
		f32_le:
			writer.write_byte(0x5F)
		f32_ge:
			writer.write_byte(0x60)

		f64_eq:
			writer.write_byte(0x61)
		f64_ne:
			writer.write_byte(0x62)
		f64_lt:
			writer.write_byte(0x63)
		f64_gt:
			writer.write_byte(0x64)
		f64_le:
			writer.write_byte(0x65)
		f64_ge:
			writer.write_byte(0x66)

		i32_clz:
			writer.write_byte(0x67)
		i32_ctz:
			writer.write_byte(0x68)
		i32_popcnt:
			writer.write_byte(0x69)
		i32_add:
			writer.write_byte(0x6A)
		i32_sub:
			writer.write_byte(0x6B)
		i32_mul:
			writer.write_byte(0x6C)
		i32_div_s:
			writer.write_byte(0x6D)
		i32_div_u:
			writer.write_byte(0x6E)
		i32_rem_s:
			writer.write_byte(0x6F)
		i32_rem_u:
			writer.write_byte(0x70)
		i32_and:
			writer.write_byte(0x71)
		i32_or:
			writer.write_byte(0x72)
		i32_xor:
			writer.write_byte(0x73)
		i32_shl:
			writer.write_byte(0x74)
		i32_shr_s:
			writer.write_byte(0x75)
		i32_shr_u:
			writer.write_byte(0x76)
		i32_rotl:
			writer.write_byte(0x77)
		i32_rotr:
			writer.write_byte(0x78)

		i64_clz:
			writer.write_byte(0x79)
		i64_ctz:
			writer.write_byte(0x7A)
		i64_popcnt:
			writer.write_byte(0x7B)
		i64_add:
			writer.write_byte(0x7C)
		i64_sub:
			writer.write_byte(0x7D)
		i64_mul:
			writer.write_byte(0x7E)
		i64_div_s:
			writer.write_byte(0x7F)
		i64_div_u:
			writer.write_byte(0x80)
		i64_rem_s:
			writer.write_byte(0x81)
		i64_rem_u:
			writer.write_byte(0x82)
		i64_and:
			writer.write_byte(0x83)
		i64_or:
			writer.write_byte(0x84)
		i64_xor:
			writer.write_byte(0x85)
		i64_shl:
			writer.write_byte(0x86)
		i64_shr_s:
			writer.write_byte(0x87)
		i64_shr_u:
			writer.write_byte(0x88)
		i64_rotl:
			writer.write_byte(0x89)
		i64_rotr:
			writer.write_byte(0x8A)

		f32_abs:
			writer.write_byte(0x8B)
		f32_neg:
			writer.write_byte(0x8C)
		f32_ceil:
			writer.write_byte(0x8D)
		f32_floor:
			writer.write_byte(0x8E)
		f32_trunc:
			writer.write_byte(0x8F)
		f32_nearest:
			writer.write_byte(0x90)
		f32_sqrt:
			writer.write_byte(0x91)
		f32_add:
			writer.write_byte(0x92)
		f32_sub:
			writer.write_byte(0x93)
		f32_mul:
			writer.write_byte(0x94)
		f32_div:
			writer.write_byte(0x95)
		f32_min:
			writer.write_byte(0x96)
		f32_max:
			writer.write_byte(0x97)
		f32_copysign:
			writer.write_byte(0x98)

		f64_abs:
			writer.write_byte(0x99)
		f64_neg:
			writer.write_byte(0x9A)
		f64_ceil:
			writer.write_byte(0x9B)
		f64_floor:
			writer.write_byte(0x9C)
		f64_trunc:
			writer.write_byte(0x9D)
		f64_nearest:
			writer.write_byte(0x9E)
		f64_sqrt:
			writer.write_byte(0x9F)
		f64_add:
			writer.write_byte(0xA0)
		f64_sub:
			writer.write_byte(0xA1)
		f64_mul:
			writer.write_byte(0xA2)
		f64_div:
			writer.write_byte(0xA3)
		f64_min:
			writer.write_byte(0xA4)
		f64_max:
			writer.write_byte(0xA5)
		f64_copysign:
			writer.write_byte(0xA6)

		i32_wrap_i64:
			writer.write_byte(0xA7)
		i32_trunc_f32_s:
			writer.write_byte(0xA8)
		i32_trunc_f32_u:
			writer.write_byte(0xA9)
		i32_trunc_f64_s:
			writer.write_byte(0xAA)
		i32_trunc_f64_u:
			writer.write_byte(0xAB)
		i64_extend_i32_s:
			writer.write_byte(0xAC)
		i64_extend_i32_u:
			writer.write_byte(0xAD)
		i64_trunc_f32_s:
			writer.write_byte(0xAE)
		i64_trunc_f32_u:
			writer.write_byte(0xAF)
		i64_trunc_f64_s:
			writer.write_byte(0xB0)
		i64_trunc_f64_u:
			writer.write_byte(0xB1)
		f32_convert_i32_s:
			writer.write_byte(0xB2)
		f32_convert_i32_u:
			writer.write_byte(0xB3)
		f32_convert_i64_s:
			writer.write_byte(0xB4)
		f32_convert_i64_u:
			writer.write_byte(0xB5)
		f32_demote_f64:
			writer.write_byte(0xB6)
		f64_convert_i32_s:
			writer.write_byte(0xB7)
		f64_convert_i32_u:
			writer.write_byte(0xB8)
		f64_convert_i64_s:
			writer.write_byte(0xB9)
		f64_convert_i64_u:
			writer.write_byte(0xBA)
		f64_promote_f32:
			writer.write_byte(0xBB)
		i32_reinterpret_f32:
			writer.write_byte(0xBC)
		i64_reinterpret_f64:
			writer.write_byte(0xBD)
		f32_reinterpret_i32:
			writer.write_byte(0xBE)
		f64_reinterpret_i64:
			writer.write_byte(0xBF)

		i32_extend8_s:
			writer.write_byte(0xC0)
		i32_extend16_s:
			writer.write_byte(0xC1)
		i64_extend8_s:
			writer.write_byte(0xC2)
		i64_extend16_s:
			writer.write_byte(0xC3)
		i64_extend32_s:
			writer.write_byte(0xC4)

		ref_func(funcidx):
			writer.write_byte(0xD2)
			writer.write_u32(funcidx)
		ref_null(ty):
			writer.write_byte(0xD0)
			pack_heap_type(writer, ty)
		ref_is_null:
			writer.write_byte(0xD1)
		ref_as_non_null:
			writer.write_byte(0xD4)
		ref_eq:
			writer.write_byte(0xD3)
		ref_cast(ty):
			writer.write_byte(0xFB)
			writer.write_u32(23 if ty.nullable else 22)
			pack_heap_type(writer, ty.heap_type)
		struct_new(ty):
			writer.write_byte(0xFB)
			writer.write_u32(0)
			writer.write_u32(ty)
		struct_get(ty, field):
			writer.write_byte(0xFB)
			writer.write_u32(2)
			writer.write_u32(ty)
			writer.write_u32(field)
		struct_set(ty, field):
			writer.write_byte(0xFB)
			writer.write_u32(5)
			writer.write_u32(ty)
			writer.write_u32(field)
		array_new_fixed(ty, size):
			writer.write_byte(0xFB)
			writer.write_u32(8)
			writer.write_u32(ty)
			writer.write_u32(size)
		array_new_data(ty, dataidx):
			writer.write_byte(0xFB)
			writer.write_u32(9)
			writer.write_u32(ty)
			writer.write_u32(dataidx)
		array_new_elem(ty, elemidx):
			writer.write_byte(0xFB)
			writer.write_u32(10)
			writer.write_u32(ty)
			writer.write_u32(elemidx)
		array_new_default(ty):
			writer.write_byte(0xFB)
			writer.write_u32(7)
			writer.write_u32(ty)
		array_get(ty):
			writer.write_byte(0xFB)
			writer.write_u32(11)
			writer.write_u32(ty)
		array_set(ty):
			writer.write_byte(0xFB)
			writer.write_u32(14)
			writer.write_u32(ty)
		ref_i31:
			writer.write_byte(0xFB)
			writer.write_u32(28)
		i31_get(signed):
			writer.write_byte(0xFB)
			writer.write_u32(29 if signed else 30)
		extern_convert_any:
			writer.write_byte(0xFB)
			writer.write_u32(27)
		any_convert_extern:
			writer.write_byte(0xFB)
			writer.write_u32(26)

fn pack_value_type(writer: Writer, ty?: ValueType):
	case ty:
		Num(t):
			case t:
				f64: writer.write_byte(0x7C)
				f32: writer.write_byte(0x7D)
				i64: writer.write_byte(0x7E)
				i32: writer.write_byte(0x7F)
		Ref(t):
			case t.heap_type:
				TypeIdx(index):
					writer.write_byte(0x63 if t.nullable else 0x64)
					writer.write_s32(index)
			else:
				if not t.nullable:
					writer.write_byte(0x64)
				pack_heap_type(writer, t.heap_type)

fn pack_heap_type(writer: Writer, ty?: HeapType):
	case ty:
		Any:
			writer.write_byte(0x6E)
		Func:
			writer.write_byte(0x70)
		i31:
			writer.write_byte(0x6C)
		Extern:
			writer.write_byte(0x6F)
		TypeIdx(index):
			writer.write_s32(index)

fn pack_field_type(writer: Writer, field?: FieldType):
	case field.ty:
		Value(t):
			pack_value_type(writer, t)
		Packed(t):
			case t:
				i16: writer.write_byte(0x77)
				i8: writer.write_byte(0x78)
	writer.write_byte(0x1 if field.mutable else 0x0)

fn pack_str(writer: Writer, text?: str):
	writer.write_u32(str_len(text))
	writer.write_data(bytes_from_ascii(text))

fn write_header(writer: Writer):
	# Magic:
	writer.write_byte(0x00)
	writer.write_byte(0x61)
	writer.write_byte(0x73)
	writer.write_byte(0x6D)

	# Version:
	writer.write_byte(0x01)
	writer.write_byte(0x00)
	writer.write_byte(0x00)
	writer.write_byte(0x00)

fn write_section(writer: Writer, id: int, data: Bytes):
	"""Write a section with given ID and data."""
	writer.write_byte(id)
	writer.write_u32(data.len())
	writer.write_data(data)

fn create_type_section(wasm_module: Module) -> Bytes:
	"""Create data for the type section"""
	let writer = Writer()
	writer.write_u32(wasm_module.types.len())
	for ty in wasm_module.types:
		case ty:
			Struct(fields):
				writer.write_byte(0x5F)
				writer.write_u32(fields.len())
				for field in fields:
					pack_field_type(writer, field)
			Array(ty):
				writer.write_byte(0x5E)
				pack_field_type(writer, ty)
			Func(params, results):
				writer.write_byte(0x60)
				writer.write_u32(params.len())
				for param in params:
					pack_value_type(writer, param)
				writer.write_u32(results.len())
				for result in results:
					pack_value_type(writer, result)

	writer.get_bytes()

fn create_import_section(wasm_module: Module) -> Bytes:
	let writer = Writer()
	writer.write_u32(wasm_module.imports.len())
	for imp in wasm_module.imports:
		pack_str(writer, imp.modname)
		pack_str(writer, imp.name)
		case imp.kind:
			Func(index):
				writer.write_byte(0x00)
				writer.write_u32(index)
			Global(ty, mutable):
				writer.write_byte(0x03)
				pack_value_type(writer, ty)
				writer.write_byte(0x1 if mutable else 0x0)
			Tag(typeidx):
				writer.write_byte(0x04)
				writer.write_byte(0x00)
				writer.write_u32(typeidx)
	writer.get_bytes()

fn create_func_section(wasm_module: Module) -> Bytes:
	let writer = Writer()
	writer.write_u32(wasm_module.functions.len())
	for function in wasm_module.functions:
		writer.write_u32(function.typeidx)
	writer.get_bytes()

fn create_global_section(wasm_module: Module) -> Bytes:
	let writer = Writer()
	writer.write_u32(wasm_module.globals.len())
	for g in wasm_module.globals:
		pack_value_type(writer, g.ty)
		writer.write_byte(0x1 if g.mutable else 0x0)
		for instruction in g.value:
			encode(writer, instruction)
		writer.write_byte(0xB)  # End opcode
	writer.get_bytes()

fn write_export_section(wasm_module: Module) -> Bytes:
	let writer = Writer()
	writer.write_u32(wasm_module.exports.len())
	for e in wasm_module.exports:
		pack_str(writer, e.name)
		case e.kind:
			Func(index):
				writer.write_byte(0x00)
				writer.write_u32(index)
			Global(index):
				writer.write_byte(0x03)
				writer.write_u32(index)
			Memory(memidx):
				writer.write_byte(0x02)
				writer.write_u32(memidx)
			Tag(tagidx):
				writer.write_byte(0x04)
				writer.write_u32(tagidx)
			Table(tableidx):
				writer.write_byte(0x01)
				writer.write_u32(tableidx)
	writer.get_bytes()

fn write_code_section(wasm_module: Module) -> Bytes:
	let writer = Writer()
	writer.write_u32(wasm_module.functions.len())
	for function in wasm_module.functions:
		let code = write_code(function)
		writer.write_u32(code.len())
		writer.write_data(code)
	writer.get_bytes()

fn write_code(function: Function) -> Bytes:
	let writer = Writer()
	writer.write_u32(function.locals.len())
	for local in function.locals:
		writer.write_u32(1)  # could be more than 1
		pack_value_type(writer, local)

	for instruction in function.code:
		encode(writer, instruction)
	writer.write_byte(0xB)  # Some extra end opcode, just for good measure.
	writer.get_bytes()

fn write_data_section(wasm_module: Module) -> Bytes:
	let writer = Writer()
	writer.write_u32(wasm_module.datas.len())
	for data in wasm_module.datas:
		# Passive data:
		writer.write_u32(1)
		writer.write_u32(data.data.len())
		writer.write_data(data.data)
	writer.get_bytes()

fn write_data_count_section(wasm_module: Module) -> Bytes:
	let writer = Writer()
	writer.write_u32(wasm_module.datas.len())
	writer.get_bytes()

fn write_tag_section(wasm_module: Module) -> Bytes:
	let writer = Writer()
	writer.write_u32(wasm_module.tags.len())
	for tag in wasm_module.tags:
		writer.write_byte(0x00)
		writer.write_u32(tag.typeidx)
	writer.get_bytes()

pub fn to_wasm(wasm_module: Module) -> Bytes:
	"""Create binary representation of wasm module."""
	let writer = Writer()
	write_header(writer)
	write_section(writer, id: 1, data: create_type_section(wasm_module))
	write_section(writer, id: 2, data: create_import_section(wasm_module))
	write_section(writer, id: 3, data: create_func_section(wasm_module))
	# 4 table section
	# 5 memory section
	if not wasm_module.tags.is_empty():
		write_section(writer, id: 13, data: write_tag_section(wasm_module))
	if not wasm_module.globals.is_empty():
		write_section(writer, id: 6, data: create_global_section(wasm_module))
	write_section(writer, id: 7, data: write_export_section(wasm_module))
	# 8 start section
	# 9 element section
	if not wasm_module.datas.is_empty():
		write_section(writer, id: 12, data: write_data_count_section(wasm_module))
	write_section(writer, id: 10, data: write_code_section(wasm_module))
	if not wasm_module.datas.is_empty():
		write_section(writer, id: 11, data: write_data_section(wasm_module))
	writer.get_bytes()

fn block_type_to_string(block_type: BlockType) -> str:
	var res = ""
	# TODO: params
	if not block_type.results.is_empty():
		let parts2: List[str] = List()
		fuu(label: "result", items: block_type.results, parts2)
		res = res + " " + str_join(parts: parts2, sep: " ")
	res

fn catch_to_string(catch: CatchItem) -> str:
	case catch:
		Catch(tagindex, labelidx):
			"(catch {tagindex} {labelidx})"

fn to_string(instruction: Instruction) -> str:
	case instruction:
		ctrl_unreachable: "unreachable"
		ctrl_nop: "nop"
		drop: "drop"
		ctrl_block(block_type):
			"block" + block_type_to_string(block_type)
		ctrl_loop(block_type):
			"loop" + block_type_to_string(block_type)
		ctrl_if(block_type):
			"if" + block_type_to_string(block_type)
		ctrl_else: "else"
		ctrl_end: "end"

		ctrl_br(labelidx): "br {labelidx}"
		ctrl_br_if(labelidx): "br_if {labelidx}"
		ctrl_br_table: "br_table"
		ctrl_return: "return"
		ctrl_call(funcidx): "call {funcidx}"
		ctrl_call_ref(ty): "call_ref {ty}"
		ctrl_call_indirect(tableidx): "call_indirect {tableidx}"
		ctrl_throw(index): "throw {index}"
		ctrl_try_table(block_type, catches):
			var res = "try_table" + block_type_to_string(block_type)
			for catch in catches:
				res = res + " " + catch_to_string(catch)
			res
		local_get(localidx): "local.get {localidx}"
		local_set(localidx): "local.set {localidx}"
		local_tee(localidx): "local.tee {localidx}"
		global_get(globalidx): "global.get {globalidx}"
		global_set(globalidx): "global.set {globalidx}"

		i32_load(align, offset): "i32.load offset={offset} align={align}"
		i64_load(align, offset): "i64.load offset={offset} align={align}"
		f32_load(align, offset): "f32.load offset={offset} align={align}"
		f64_load(align, offset): "f64.load offset={offset} align={align}"
		i32_store(align, offset): "i32.store offset={offset} align={align}"
		i64_store(align, offset): "i64.store offset={offset} align={align}"
		f32_store(align, offset): "f32.store offset={offset} align={align}"
		f64_store(align, offset): "f64.store offset={offset} align={align}"

		i32_const(value): "i32.const {value}"
		i64_const(value): "i64.const {value}"
		f32_const(value): "f32.const {float_to_str2(value: float(value), digits: 20)}"
		f64_const(value): "f64.const {float_to_str2(value, digits: 20)}"

		i32_eqz: "i32.eqz"
		i32_eq: "i32.eq"
		i32_ne: "i32.ne"
		i32_lt_s: "i32.lt_s"
		i32_lt_u: "i32.lt_u"
		i32_gt_s: "i32.gt_s"
		i32_gt_u: "i32.gt_u"
		i32_le_s: "i32.le_s"
		i32_le_u: "i32.le_u"
		i32_ge_s: "i32.ge_s"
		i32_ge_u: "i32.ge_u"

		i64_eqz: "i64.eqz"
		i64_eq: "i64.eq"
		i64_ne: "i64.ne"
		i64_lt_s: "i64.lt_s"
		i64_lt_u: "i64.lt_u"
		i64_gt_s: "i64.gt_s"
		i64_gt_u: "i64.gt_u"
		i64_le_s: "i64.le_s"
		i64_le_u: "i64.le_u"
		i64_ge_s: "i64.ge_s"
		i64_ge_u: "i64.ge_u"

		f32_eq: "f32.eq"
		f32_ne: "f32.ne"
		f32_lt: "f32.lt"
		f32_gt: "f32.gt"
		f32_le: "f32.le"
		f32_ge: "f32.ge"

		f64_eq: "f64.eq"
		f64_ne: "f64.ne"
		f64_lt: "f64.lt"
		f64_gt: "f64.gt"
		f64_le: "f64.le"
		f64_ge: "f64.ge"

		i32_clz: "i32.clz"
		i32_ctz: "i32.ctz"
		i32_popcnt: "i32.popcnt"
		i32_add: "i32.add"
		i32_sub: "i32.sub"
		i32_mul: "i32.mul"
		i32_div_s: "i32.div_s"
		i32_div_u: "i32.div_u"
		i32_rem_s: "i32.rem_s"
		i32_rem_u: "i32.rem_u"
		i32_and: "i32.and"
		i32_or: "i32.or"
		i32_xor: "i32.xor"
		i32_shl: "i32.shl"
		i32_shr_s: "i32.shr_s"
		i32_shr_u: "i32.shr_u"
		i32_rotl: "i32.rotl"
		i32_rotr: "i32.rotr"

		i64_clz: "i64.clz"
		i64_ctz: "i64.ctz"
		i64_popcnt: "i64.popcnt"
		i64_add: "i64.add"
		i64_sub: "i64.sub"
		i64_mul: "i64.mul"
		i64_div_s: "i64.div_s"
		i64_div_u: "i64.div_u"
		i64_rem_s: "i64.rem_s"
		i64_rem_u: "i64.rem_u"
		i64_and: "i64.and"
		i64_or: "i64.or"
		i64_xor: "i64.xor"
		i64_shl: "i64.shl"
		i64_shr_s: "i64.shr_s"
		i64_shr_u: "i64.shr_u"
		i64_rotl: "i64.rotl"
		i64_rotr: "i64.rotr"

		f32_abs: "f32.abs"
		f32_neg: "f32.neg"
		f32_ceil: "f32.ceil"
		f32_floor: "f32.floor"
		f32_trunc: "f32.trunc"
		f32_nearest: "f32.nearest"
		f32_sqrt: "f32.sqrt"
		f32_add: "f32.add"
		f32_sub: "f32.sub"
		f32_mul: "f32.mul"
		f32_div: "f32.div"
		f32_min: "f32.min"
		f32_max: "f32.max"
		f32_copysign: "f32.copysign"

		f64_abs: "f64.abs"
		f64_neg: "f64.neg"
		f64_ceil: "f64.ceil"
		f64_floor: "f64.floor"
		f64_trunc: "f64.trunc"
		f64_nearest: "f64.nearest"
		f64_sqrt: "f64.sqrt"
		f64_add: "f64.add"
		f64_sub: "f64.sub"
		f64_mul: "f64.mul"
		f64_div: "f64.div"
		f64_min: "f64.min"
		f64_max: "f64.max"
		f64_copysign: "f64.copysign"

		i32_wrap_i64: "i32.wrap_i64"
		i32_trunc_f32_s: "i32.trunc_f32_s"
		i32_trunc_f32_u: "i32.trunc_f32_u"
		i32_trunc_f64_s: "i32.trunc_f64_s"
		i32_trunc_f64_u: "i32.trunc_f64_u"
		i64_extend_i32_s: "i64.extend_i32_s"
		i64_extend_i32_u: "i64.extend_i32_u"
		i64_trunc_f32_s: "i64.trunc_f32_s"
		i64_trunc_f32_u: "i64.trunc_f32_u"
		i64_trunc_f64_s: "i64.trunc_f64_s"
		i64_trunc_f64_u: "i64.trunc_f64_u"
		f32_convert_i32_s: "f32.convert_i32_s"
		f32_convert_i32_u: "f32.convert_i32_u"
		f32_convert_i64_s: "f32.convert_i64_s"
		f32_convert_i64_u: "f32.convert_i64_u"
		f32_demote_f64: "f32.demote_f64"
		f64_convert_i32_s: "f64.convert_i32_s"
		f64_convert_i32_u: "f64.convert_i32_u"
		f64_convert_i64_s: "f64.convert_i64_s"
		f64_convert_i64_u: "f64.convert_i64_u"
		f64_promote_f32: "f64.promote_f32"
		i32_reinterpret_f32: "i32.reinterpret_f32"
		i64_reinterpret_f64: "i64.reinterpret_f64"
		f32_reinterpret_i32: "f32.reinterpret_i32"
		f64_reinterpret_i64: "f64.reinterpret_i64"

		i32_extend8_s: "i32.extend8_s"
		i32_extend16_s: "i32.extend16_s"
		i64_extend8_s: "i64.extend8_s"
		i64_extend16_s: "i64.extend16_s"
		i64_extend32_s: "i64.extend32_s"

		ref_func(funcidx): "ref.func {funcidx}"
		ref_null(ty): "ref.null {heap_type_to_string(heap_type: ty)}"
		ref_is_null: "ref.is_null"
		ref_as_non_null: "ref.as_non_null"
		ref_eq: "ref.eq"
		ref_cast(ty): "ref.cast {ref_type_to_string(ty)}"
		struct_new(ty): "struct.new {ty}"
		struct_get(ty, field): "struct.get {ty} {field}"
		struct_set(ty, field): "struct.set {ty} {field}"
		array_new_fixed(ty, size): "array.new_fixed {ty} {size}"
		array_new_data(ty, dataidx): "array.new_data {ty} {dataidx}"
		array_new_elem(ty, elemidx): "array.new_elem {ty} {elemidx}"
		array_new_default(ty): "array.new_default {ty}"
		array_get(ty): "array.get {ty}"
		array_set(ty): "array.set {ty}"
		ref_i31: "ref.i31"
		i31_get(signed): "i31.get_" + ("s" if signed else "u")
		extern_convert_any: "extern.convert_any"
		any_convert_extern: "any.convert_extern"

pub fn to_wat(wasm_module: Module, out: TextGenerator):
	"""Write webassembly module in text format (WAT)"""

	out.emit("(module")
	out.indent()
	var type_index = 0
	for ty in wasm_module.types:
		let type_txt = comp_type_to_string(ty)
		out.emit("(type (;{type_index};) {type_txt})")
		type_index += 1

	var func_index = 0
	var global_index = 0
	for imp in wasm_module.imports:
		out.write("(import \"{imp.modname}\" \"{imp.name}\" ")
		case imp.kind:
			Func(typeidx):
				out.write("(func (;{func_index};) (type {typeidx}))")
				func_index += 1
			Global(ty, mutable):
				let ty_text = value_type_to_string(ty)
				let mutable_ty_text = "(mut {ty_text})" if mutable else ty_text
				out.write("(global (;{global_index};) {mutable_ty_text})")
				global_index += 1
			Tag(typeidx):
				out.write("(tag (type {typeidx}))")
		out.emit(")")

	for tag in wasm_module.tags:
		out.emit("(tag (type {tag.typeidx}))")

	for g in wasm_module.globals:
		let ty_text = value_type_to_string(g.ty)
		let mutable_ty_text = "(mut {ty_text})" if g.mutable else ty_text
		out.emit("(global (;{global_index};) {mutable_ty_text}")
		out.indent()
		for instruction in g.value:
			out.emit("{to_string(instruction)}")
		out.dedent()
		out.emit(")")
		global_index += 1

	for ex in wasm_module.exports:
		out.write("(export \"{ex.name}\" ")
		case ex.kind:
			Func(funcidx):
				out.write("(func {funcidx})")
			Global(globalidx):
				out.write("(global {globalidx})")
			Tag(tagidx):
				out.write("(tag {tagidx})")
			Memory(memidx):
				out.write("(memory {memidx})")
			Table(tableidx):
				out.write("(table {tableidx})")
		out.emit(")")

	for function in wasm_module.functions:
		out.emit("(func (;{func_index};) (type {function.typeidx})")
		out.indent()
		for local in function.locals:
			out.emit("(local {value_type_to_string(ty: local)})")

		for instruction in function.code:
			out.emit("{to_string(instruction)}")
		out.dedent()
		out.emit(")")
		func_index += 1

	for data in wasm_module.datas:
		# Go for passive strings now:
		out.emit("(data \"{escape_binary(data.data)}\")")

	out.dedent()
	out.emit(")")

fn escape_binary(data?: Bytes) -> str:
	var res = ""
	for b in data:
		let h1 = (b >> 4) & 0xF
		let h2 = b & 0xF
		res = res + "\\{hex_char(h1)}{hex_char(h2)}"
	res
