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

	pub fn add_use(r: Register):
		uses.append(r)

	pub fn add_def(r: Register):
		defs.append(r)

pub struct Register:
	kind: int
	color: int
