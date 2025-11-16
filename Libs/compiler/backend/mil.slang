""" Machine intermediate language.

Machine instructions are selected in this representation.

"""

from vectype import Vector, new_vector

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

	pub fn add_def(r?: Register):
		defs.append(r)

	pub fn add_clobber(r?: Register):
		clobbers.append(r)

pub struct Register:
	id: int
	kind: int
	color: int
