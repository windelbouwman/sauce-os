""" Interference graph.
"""

from logging import log_debug
from hashmap import HashMap, new_hashmap_int, new_hashmap_str
from vectype import Vector, new_vector
from settype import Set, new_int_set, new_str_set
from bitset import BitSet
from listtype import List
from strlib import str_join
from utils import panic
import mil

pub class ControlFlowGraph[V]:
	pub var m_nodes: List[ControlFlowGraphNode[V]] = List()
	var m_edges: HashMap[str,Set[str]] = new_hashmap_str()
	var m_nodes_by_name: HashMap[str,ControlFlowGraphNode[V]] = new_hashmap_str()

	pub fn add_node(node?: ControlFlowGraphNode[V]):
		m_nodes.append(node)
		m_nodes_by_name.insert(key: node.block.name, value: node)
		m_edges.insert(key: node.block.name, value: new_str_set())

	pub fn get_node(name?: str) -> ControlFlowGraphNode[V]:
		m_nodes_by_name.get(key: name)

	pub fn add_edge(name: str, dst: str):
		let x = m_edges.get(key: name)
		x.add(dst)

	pub fn get_successors(node: ControlFlowGraphNode[V]) -> List[ControlFlowGraphNode[V]]:
		let s: List[ControlFlowGraphNode[V]] = List()
		for name in m_edges.get(key: node.block.name):
			s.append(get_node(name))
		s

pub class ControlFlowGraphNode[V]:
	pub var m_gen: Set[int]
	pub var m_kill: Set[int]
	pub var m_live_in: Set[int] = new_int_set()
	pub var m_live_out: Set[int] = new_int_set()
	pub var block: mil.Block[V]

pub fn create_interference_graph[V](mfunc: mil.Function[V]) -> InterferenceGraph:
	""" Create interference graph

	See also:
	https://en.wikipedia.org/wiki/Live-variable_analysis
	"""

	let ig = InterferenceGraph()

	let cfg: ControlFlowGraph[V] = ControlFlowGraph()
	for mblock in mfunc.blocks:
		# gen and kill sets for this block:
		var full_gen: Set[int] = new_int_set()
		var full_kill: Set[int] = new_int_set()
		for mi in mblock.instructions:
			let ins_gen: Set[int] = new_int_set()
			let ins_kill: Set[int] = new_int_set()
			# Register definition kill live range:
			for reg in mi.defs:
				ins_kill.add(reg.id)
				get_ig_node(ig, reg)
				# log_debug("kill: {r.id}")

			# Register use generates a live register:
			for reg in mi.uses:
				ins_gen.add(reg.id)
				# log_debug("gen: {r.id}")

			# Combine effect:
			full_gen = full_gen.union(ins_gen.difference(full_kill))
			full_kill = full_kill.union(ins_kill)
		let node: ControlFlowGraphNode[V] = ControlFlowGraphNode(m_gen: full_gen, m_kill: full_kill, block: mblock)
		cfg.add_node(node)

	for mblock in mfunc.blocks:
		for dst in mblock.jump_targets:
			cfg.add_edge(name: mblock.name, dst)

	# Fixed point data flow:
	var n_iterations = 0
	loop:
		n_iterations += 1
		var change = false
		for node in cfg.m_nodes:
			let old_live_in = node.m_live_in
			let old_live_out = node.m_live_out
			node.m_live_in = node.m_gen.union(node.m_live_out.difference(node.m_kill))
			node.m_live_out = new_int_set()

			# include successors:
			for successor in cfg.get_successors(node):
				node.m_live_out = node.m_live_out.union(successor.m_live_in)
			if not old_live_in.equals(node.m_live_in) or not old_live_out.equals(node.m_live_out):
				change = true
		if not change:
			break
	log_debug("Iterations: {n_iterations}")


	let reg_map = new_hashmap_int()
	for n in cfg.m_nodes:
		let block = n.block
		var live_registers: Set[int] = n.m_live_out
		var index = block.instructions.len()
		while index > 0:
			index -= 1
			let mi = block.instructions.get(index)

			let ins_kill: Set[int] = new_int_set()
			for reg in mi.defs:
				ins_kill.add(reg.id)
				get_ig_node(ig, reg)

			let ins_gen: Set[int] = new_int_set()
			for reg in mi.uses:
				ins_gen.add(reg.id)
				get_ig_node(ig, reg)

			for a in live_registers:
				let n1 = ig.get_node(id: a)
				# other live registers interfere:
				for b in live_registers:
					let n2 = ig.get_node(id: b)
					if a != b:
						ig.add_edge(n1, n2)
				# clobber registers interfere:
				for clobber in mi.clobbers:
					get_ig_node(ig, reg: clobber)
					let b = clobber.id
					let n2 = ig.get_node(id: b)
					if a != b:
						ig.add_edge(n1, n2)

			live_registers = ins_gen.union(live_registers.difference(ins_kill))
	ig

fn get_ig_node(ig: InterferenceGraph, reg: mil.Register):
	if not ig.has_node(reg.id):
		let n = ig.add_node(id: reg.id, kind: reg.kind)
		n.add_reg(reg)
		if reg.color >= 0:
			n.set_color(reg.color)

pub class InterferenceGraph:
	var m_nodes: HashMap[int,IGNode] = new_hashmap_int()
	var m_adj: HashMap[int,Set[int]] = new_hashmap_int()

	pub fn mask(n?: IGNode):
		if not n.masked:
			n.masked = true
			for m_id in get_adj_set(n):
				let m = m_nodes.get(key: m_id)
				m.degree -= 1
		else:
			panic("Node already masked")

	pub fn unmask(n?: IGNode):
		if n.masked:
			n.masked = false
			for m_id in get_adj_set(n):
				let m = m_nodes.get(key: m_id)
				m.degree += 1
		else:
			panic("Node already un-masked")

	pub fn is_masked(n?: IGNode) -> bool:
		n.masked

	pub fn has_node(id?: int) -> bool:
		m_nodes.contains(key: id)

	pub fn add_node(id: int, kind: int) -> IGNode:
		if m_nodes.contains(key: id):
			m_nodes.get(key: id)
		else:
			let n = IGNode(id, kind)
			m_nodes.insert(key: id, value: n)
			m_adj.insert(key: id, value: new_int_set())
			n

	pub fn get_node(id: int) -> IGNode:
		if m_nodes.contains(key: id):
			m_nodes.get(key: id)
		else:
			panic("No node with id: {id}")

	pub fn nodes() -> List[IGNode]:
		let res: List[IGNode] = List()
		for n in m_nodes:
			res.append(m_nodes.get(key: n))
		res

	pub fn adjecent(n?: IGNode) -> List[IGNode]:
		""" Get a list of all non-masked neighbours """
		let res: List[IGNode] = List()
		for m_id in get_adj_set(n):
			let m = m_nodes.get(key: m_id)
			if not is_masked(m):
				res.append(m)
		res

	pub fn add_edge(a?: IGNode, b?: IGNode):
		# assert(condition: a != b, message: "a must not be b")
		if not has_edge(a, b):
			a.degree += 1
			b.degree += 1
			let m1 = get_adj_set(a)
			m1.add(b.id)
			let m2 = get_adj_set(b)
			m2.add(a.id)

	pub fn has_edge(a?: IGNode, b?: IGNode) -> bool:
		# assert(condition: a != b, message: "a must not be b")
		get_adj_set(a).contains(b.id)

	fn get_adj_set(n?: IGNode) -> Set[int]:
		m_adj.get(key: n.id)

	fn get_degree(n?: IGNode) -> int:
		get_adj_set(n).len()

pub class IGNode:
	""" Node in the interference graph. """
	pub var id: int
	pub var color: int = -1
	pub var kind: int
	pub var degree: int = 0
	pub var masked: bool = false

	pub var regs: List[mil.Register] = List()

	pub fn add_reg(reg: mil.Register):
		regs.append(reg)

	pub fn set_color(c?: int):
		color = c
		for reg in regs:
			reg.color = c

	pub fn is_colored() -> bool:
		color >= 0

	pub fn to_string() -> str:
		let parts: List[str] = List()
		for reg in regs:
			parts.append(mil.vr_to_str(reg))
		let txt = str_join(parts, sep: ",")
		"IGNode(degree={degree},regs=[{txt}]"
