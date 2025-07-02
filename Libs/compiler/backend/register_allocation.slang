""" Register allocation

This function is machine independant. It assigns colors to use / def registers.
"""

from utils import log_info
from vectype import Vector
from optiontype import Option

pub fn reg_alloc[X,R](mfunc: MachineFunction[X,R]):
	""" Implement iterated register allocation """
	log_info("Reg-alloc {mfunc.name}")
	let cfg = create_cfg(mfunc)
	let ig = create_interference_graph(cfg)

	# Color the interference graph

fn create_cfg[X,R](mfunc: MachineFunction[X,R]) -> int:
	""" Create control flow graph """
	0

fn create_interference_graph(cfg: int) -> int:
	""" Create interference graph """
	#for block in cfg:
	#   for instruction in block:
	pass
	#live_regs
	# add edges between live registers
	#for n1, n2 in pairs(live_regs):
	#    add_edge(n1, n2)
	1

pub struct MachineInstruction[X,R]:
	instruction: X
	uses: Vector[int]
	defs: Vector[int]
	relocation: Option[R]

pub struct MachineBlock[X,R]:
	name: str
	instructions: Vector[MachineInstruction[X,R]]

pub struct MachineFunction[X,R]:
	name: str
	blocks: Vector[MachineBlock[X,R]]
