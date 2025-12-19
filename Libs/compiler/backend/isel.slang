""" Instruction selection related code.

"""

from listtype import List
from hashmap import HashMap, new_hashmap_str, new_hashmap_int
from vectype import Vector, new_vector
from bytes import ByteArray
from outstream import BinaryOutput, DataItem
import sil
import mil

pub struct Backend[V]:
	""" Backend based on first instruction selection, then register allocation. """
	all_regs: List[int]  # int regs
	all_regs2: List[int]  # Float regs
	enter: fn(SelectionContext[V], sil.Function)
	selector: fn(SelectionContext[V], sil.Instruction)
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

pub class SelectionContext[V]:
	var codes: Vector[mil.Instruction[V]] = new_vector()
	var m_tmp_regs: HashMap[str,mil.Register] = new_hashmap_str()
	var m_pre_colored_regs: HashMap[int,mil.Register] = new_hashmap_int()
	var m_counter: int = 0
	pub var frame: Frame

	pub fn get_value_vreg(value?: sil.Value) -> mil.Register:
		get_vreg_for_tmp(name: value.name, ty: value.ty)

	pub fn set_vreg_for_tmp(name: str, register: mil.Register):
		m_tmp_regs.insert(key: name, value: register)

	pub fn get_vreg_for_tmp(name: str, ty: sil.Type) -> mil.Register:
		if m_tmp_regs.contains(key: name):
			m_tmp_regs.get(key: name)
		else:
			let kind: int = case ty:
				F64: 1
				F32: 1
				I64: 0
				I32: 0
				I16: 0
				I8: 0
			let r = new_vreg(kind)
			m_tmp_regs.insert(key: name, value: r)
			r

	pub fn get_pre_colored(color: int, kind: int) -> mil.Register:
		# TODO: maybe index by tuple of color/kind?
		let key = 1000 * kind + color
		if m_pre_colored_regs.contains(key):
			m_pre_colored_regs.get(key)
		else:
			let r = new_vreg(kind)
			r.color = color
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

	pub fn new_vreg(kind: int) -> mil.Register:
		m_counter += 1
		let color = -1
		mil.Register(id: m_counter, color, kind)
