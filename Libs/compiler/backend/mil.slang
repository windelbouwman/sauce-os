""" Machine intermediate language.

Machine instructions are selected in this representation.

"""

from vectype import Vector, new_vector
from listtype import List
from strlib import str_join
from report import Report

pub struct Function[X]:
	name: str
	blocks: Vector[Block[X]]

pub struct Block[X]:
	""" Basic block """
	name: str
	instructions: Vector[Instruction[X]]

pub class Instruction[X]:
	pub var instruction: X
	pub var uses: Vector[Register] = new_vector()
	pub var defs: Vector[Register] = new_vector()
	pub var clobbers: Vector[Register] = new_vector()
	pub var is_move: bool = false

	pub fn add_use(r?: Register):
		uses.append(r)

	pub fn is_reg_used(r?: Register) -> bool:
		does_contain(registers: uses, register: r)

	pub fn add_def(r?: Register):
		defs.append(r)

	pub fn is_reg_defined(r?: Register) -> bool:
		does_contain(registers: defs, register: r)

	pub fn add_clobber(r?: Register):
		clobbers.append(r)

fn does_contain(registers: Vector[Register], register: Register) -> bool:
	for r in registers:
		if r.id == register.id:
			return true
	false

pub struct Register:
	id: int
	kind: int
	color: int

pub fn dump_mfunc[V](report: Report, mfunc: Function[V], to_str: fn(V) -> str):
	if not report.is_enabled():
		return
	report.heading("Function '{mfunc.name}")
	for mblock in mfunc.blocks:
		report.writeln("  Block '{mblock.name}'")
		for minst in mblock.instructions:
			let txt = to_str(minst.instruction)
			let defs = regs_to_str(label: "defs", regs: minst.defs)
			let uses = regs_to_str(label: "uses", regs: minst.uses)
			let clobbers = regs_to_str(label: "clobbers", regs: minst.clobbers)
			let is_move = "move" if minst.is_move else ""
			report.writeln("    > {txt}                     {defs} {uses} {clobbers} {is_move}")
	report.writeln("")

fn regs_to_str(label: str, regs: Vector[Register]) -> str:
	if regs.is_empty():
		""
	else:
		let parts: List[str] = List()
		for reg in regs:
			parts.append(vr_to_str(reg))
		let txt = str_join(parts, sep: ", ")
		"{label}=[{txt}]"

pub fn vr_to_str(reg?: Register) -> str:
	if reg.kind == 0:
		"R{reg.id}"
	elif reg.kind == 1:
		"F{reg.id}"
	else:
		"X{reg.id}"
