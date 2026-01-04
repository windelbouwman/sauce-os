""" Instruction selection related code.

"""

from listtype import List
from hashmap import HashMap, new_hashmap_int
from vectype import Vector, new_vector
from bytes import ByteArray
from outstream import BinaryOutput, DataItem
import sil
import mil

pub struct Backend[C,V]:
	""" Backend based on first instruction selection, then register allocation. """
	ctx: C
	bits: int
	all_regs: Vector[Vector[int]]  # 0=int regs,1=Float regs
	enter: fn(C, SelectionContext[V], sil.Function)
	selector: fn(C, SelectionContext[V], sil.Instruction)
	to_str: fn(V) -> str
	materializer: fn(SelectionContext[V], mil.Instruction[V], BinaryOutput)
	emit_prologue: fn(Frame, BinaryOutput)
	emit_epilogue: fn(Frame, BinaryOutput)
	fixer: fn(ByteArray, int, int, int, int)
	is_pic_reloc: fn(int) -> bool
	emit_data: fn(DataItem, BinaryOutput)

pub struct Frame:
	stacksize: int
	exit_label: str
	vregs: Vector[mil.Register]  # Number of virtual-registers used in total

pub class SelectionContext[V]:
	var codes: Vector[mil.Instruction[V]] = new_vector()
	var m_tmp_regs: HashMap[int,mil.Register] = new_hashmap_int()
	var m_pre_colored_regs: HashMap[int,mil.Register] = new_hashmap_int()
	pub var frame: Frame

	pub fn get_value_vreg(value?: sil.Value) -> mil.Register:
		get_vreg_for_tmp(id: value.id, ty: value.ty)

	pub fn set_vreg_for_value(value: sil.Value, register: mil.Register):
		m_tmp_regs.insert(key: value.id, value: register)

	fn get_vreg_for_tmp(id: int, ty: sil.Type) -> mil.Register:
		if m_tmp_regs.contains(key: id):
			m_tmp_regs.get(key: id)
		else:
			let kind: int = case ty:
				F64: 1
				F32: 1
				I64: 0
				I32: 0
				I16: 0
				I8: 0
			let r = new_vreg(kind, color: -1)
			m_tmp_regs.insert(key: id, value: r)
			r

	pub fn get_pre_colored(color: int, kind: int) -> mil.Register:
		# TODO: maybe index by tuple of color/kind?
		let key = 1000 * kind + color
		if m_pre_colored_regs.contains(key):
			m_pre_colored_regs.get(key)
		else:
			let r = new_vreg(kind, color)
			m_pre_colored_regs.insert(key, value: r)
			r

	pub fn emit(instruction?: V):
		emit_full(instruction)

	fn emit_full(instruction?: V):
		let minst = mil.Instruction(instruction)
		codes.append(minst)

	pub fn emit_minst(instruction: mil.Instruction[V]):
		codes.append(instruction)

	pub fn emit_and_get(instruction?: V) -> mil.Instruction[V]:
		emit(instruction)
		codes.last()

	pub fn get_instructions() -> Vector[mil.Instruction[V]]:
		let res = codes
		codes = new_vector()
		res

	fn new_vreg(kind: int, color: int) -> mil.Register:
		let id = frame.vregs.len()
		let vreg = mil.Register(id, color, kind)
		frame.vregs.append(vreg)
		vreg
