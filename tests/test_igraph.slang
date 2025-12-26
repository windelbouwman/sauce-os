
""" Test interference graph. """

from std import print
from unittest import assert_true
from vectype import Vector, new_vector, new_vector_with_capacity
from listtype import List
from igraph import create_interference_graph
import mil

pub fn main() -> int:
	let r0 = mil.Register(id: 0, kind: 0, color: -1)
	let r1 = mil.Register(id: 1, kind: 0, color: -1)
	let r2 = mil.Register(id: 2, kind: 0, color: -1)
	let r3 = mil.Register(id: 3, kind: 0, color: -1)
	let r4 = mil.Register(id: 4, kind: 0, color: -1)
	let r5 = mil.Register(id: 5, kind: 0, color: -1)

	let vregs: Vector[mil.Register] = new_vector_with_capacity(capacity: 6)
	vregs.append(r0)
	vregs.append(r1)
	vregs.append(r2)
	vregs.append(r3)
	vregs.append(r4)
	vregs.append(r5)

	let blocks: Vector[mil.Block[TestIns]] = new_vector()
	let instructions: Vector[mil.Instruction[TestIns]] = new_vector()

	let ins0 = mil.Instruction(instruction: TestIns.Entry())
	ins0.add_def(r0)
	ins0.add_def(r1)
	instructions.append(ins0)

	let ins1 = mil.Instruction(instruction: TestIns.Nop())
	ins1.add_use(r0)
	instructions.append(ins1)

	let ins2 = mil.Instruction(instruction: TestIns.Nop())
	ins2.add_use(r1)
	instructions.append(ins2)

	let jump_targets: List[str] = List()
	blocks.append(mil.Block(name: "start", instructions, jump_targets))

	let mfunc: mil.Function[TestIns] = mil.Function(name: "dummy", blocks)

	let ig = create_interference_graph(mfunc, vregs)
	assert_true(ig.has_edge(ig.get_node(id: 0), ig.get_node(id: 1)))
	print("OK")
	0

enum TestIns:
	Entry
	Nop
	Exit
