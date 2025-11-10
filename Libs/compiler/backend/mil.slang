""" Machine intermediate language.

Machine instructions are selected in this representation.

"""

from vectype import Vector

pub struct Function[X]:
	name: str
	blocks: Vector[Block[X]]

pub struct Block[X]:
	""" Basic block """
	name: str
	instructions: Vector[Instruction[X]]

pub class Instruction[X]:
	pub var instruction: X
	pub var uses: Vector[Register]
	pub var defs: Vector[Register]
	pub var clobbers: Vector[Register]

	pub fn add_use(r?: Register):
		uses.append(r)

	pub fn add_def(r?: Register):
		defs.append(r)

	pub fn add_clobber(r?: Register):
		clobbers.append(r)

pub struct Register:
	id: int
	kind: int
	color: int
