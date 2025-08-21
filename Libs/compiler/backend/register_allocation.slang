""" Register allocation

This function is machine independant. It assigns colors to use / def registers.
"""

from utils import log_info
import mil

pub fn reg_alloc[X](mfunc: mil.Function[X]):
	""" Implement iterated register allocation """
	log_info("Reg-alloc {mfunc.name}")
	let cfg = create_cfg(mfunc)
	let ig = create_interference_graph(cfg)

	# Color the interference graph
	for mblock in mfunc.blocks:
		for mi in mblock.instructions:
			for r in mi.defs:
				r.color = 1
			for r in mi.uses:
				r.color = 2

fn create_cfg[X](mfunc: mil.Function[X]) -> int:
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
