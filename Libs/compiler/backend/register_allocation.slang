""" Register allocation

This function is machine independant. It assigns colors to use / def registers.
"""

from utils import log_info
from settype import Set, new_int_set
from listtype import List
import mil

pub fn reg_alloc[X](mfunc: mil.Function[X]):
	""" Implement iterated register allocation """
	log_info("Reg-alloc {mfunc.name}")
	let cfg = create_cfg(mfunc)
	let ig = create_interference_graph(cfg)

	# Perform graph coloring
	# Take out nodes that can be colored
	# When the graph is empty, place the nodes back in reverse order,
	# and assign them a color

	# Color the interference graph
	for mblock in mfunc.blocks:
		for mi in mblock.instructions:
			for r in mi.defs:
				r.color = 1
			for r in mi.uses:
				r.color = 2

fn create_cfg[X](mfunc: mil.Function[X]) -> ControlFlowGraph:
	""" Create control flow graph """
	let cfg = ControlFlowGraph()
	for mblock in mfunc.blocks:
		# gen and kill sets for this block:
		var full_gen: Set[int] = new_int_set()
		var full_kill: Set[int] = new_int_set()
		for mi in mblock.instructions:
			let ins_gen: Set[int] = new_int_set()
			let ins_kill: Set[int] = new_int_set()
			# Register definition kill live range:
			for r in mi.defs:
				ins_kill.add(r.id)

			# Register use generates a live register:
			for r in mi.uses:
				ins_gen.add(r.id)

			# Combine effect:
			full_gen = full_gen.union(other: ins_gen.difference(other: full_kill))
			full_kill = full_kill.union(other: ins_kill)
		let node = ControlFlowGraphNode(m_gen: full_gen, m_kill: full_kill)
		cfg.add_node(node)
	cfg

class ControlFlowGraph:
	var m_nodes: List[ControlFlowGraphNode] = List()

	pub fn add_node(node?: ControlFlowGraphNode):
		m_nodes.append(node)

class ControlFlowGraphNode:
	var m_gen: Set[int]
	var m_kill: Set[int]

fn create_interference_graph(cfg: ControlFlowGraph) -> InterferenceGraph:
	""" Create interference graph """
	let g = InterferenceGraph()
	#for block in cfg:
	#   for instruction in block:
	pass
	#live_regs
	# add edges between live registers
	#for n1, n2 in pairs(live_regs):
	#    add_edge(n1, n2)
	g

class InterferenceGraph:
	var x: int = 0

	fn get_node():
		pass

	fn add_edge(reg1: int, reg2: int):
		pass

#class InterferenceGraphNode:
#	pass
