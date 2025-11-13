""" Register allocation

This function is machine independant.
It assigns colors to use / def registers.
"""

from logging import log_info, log_debug
from settype import Set, new_int_set
from hashmap import HashMap, new_hashmap_int
from utils import unimplemented, panic
from listtype import List
import mil

pub fn reg_alloc[V](mfunc: mil.Function[V], all_regs: List[int]):
	""" Implement iterated register allocation """
	log_info("Reg-alloc {mfunc.name}")
	let cfg: ControlFlowGraph[V] = create_cfg(mfunc)
	let ig = create_interference_graph(cfg)
	let r = RegAlloc(m_ig: ig, m_regs: all_regs)
	r.alloc()

class RegAlloc:
	""" Perform graph coloring
	Take out nodes that can be colored
	When the graph is empty, place the nodes back in reverse order,
	and assign them a color
	"""
	var m_ig: InterferenceGraph
	var m_regs: List[int]
	var m_k: int = 0
	var m_select_stack: List[IGNode] = List()
	var m_simplify_worklist: List[IGNode] = List()
	var m_spill_worklist: HashMap[int,IGNode] = new_hashmap_int()
	var m_freeze_worklist: HashMap[int,IGNode] = new_hashmap_int()
	var m_pre_colored: HashMap[int,IGNode] = new_hashmap_int()

	pub fn alloc():
		m_k = m_regs.len()
		loop:
			fill_data()
			loop:
				if not m_simplify_worklist.is_empty():
					simplify()
				else:
					break

			if not m_simplify_worklist.is_empty():
				panic("simplify list not empty")
			if not m_spill_worklist.is_empty():
				for spill_id in m_spill_worklist:
					let spill_node = m_spill_worklist.get(key: spill_id)
					log_info("> {spill_id} = {spill_node.to_string()}")
				panic("Spill list not empty")
			if not m_freeze_worklist.is_empty():
				panic("Freeze worklist not empty")
			assign_colors()
			# TODO: implement spill by re-trying the loop after code modification
			break

	fn fill_data():
		for n in m_ig.nodes():
			if n.is_colored():
				m_pre_colored.insert(key: n.id, value: n)
			elif not is_colorable(n):
				m_spill_worklist.insert(key: n.id, value: n)
			elif is_move_related(n):
				m_freeze_worklist.insert(key: n.id, value: n)
			else:
				m_simplify_worklist.append(n)

	fn simplify():
		# log_debug("simplify")
		let n = m_simplify_worklist.pop_front()
		m_select_stack.append(n)
		m_ig.mask(n)
		for m in m_ig.adjecent(n):
			if is_colorable(m) and m_spill_worklist.contains(key: m.id):
				m_spill_worklist.drop(key: m.id)
				m_simplify_worklist.append(m)

	fn assign_colors():
		""" Assign colors """
		let all_regs = new_int_set()
		for r in m_regs:
			all_regs.add(r)

		for n in m_select_stack.reversed():
			m_ig.unmask(n)
			let taken_regs = new_int_set()
			for m in m_ig.adjecent(n):
				taken_regs.add(m.color)
			let ok_regs = all_regs.difference(other: taken_regs)
			if ok_regs.is_empty():
				unimplemented("Spilling")
			else:
				let reg = ok_regs.first()
				log_debug("Color: R{n.id} {reg}")
				n.set_color(reg)

	fn is_colorable(m?: IGNode) -> bool:
		if m.is_colored():
			true
		elif m.degree < m_k:
			true
		else:
			false

	fn is_move_related(m?: IGNode) -> bool:
		false

fn create_cfg[V](mfunc: mil.Function[V]) -> ControlFlowGraph[V]:
	""" Create control flow graph (CFG) for given function """
	let cfg: ControlFlowGraph[V] = ControlFlowGraph()
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
				# log_debug("kill: {r.id}")

			# Register use generates a live register:
			for r in mi.uses:
				ins_gen.add(r.id)
				# log_debug("gen: {r.id}")

			# Combine effect:
			full_gen = full_gen.union(ins_gen.difference(full_kill))
			full_kill = full_kill.union(ins_kill)
		let node: ControlFlowGraphNode[V] = ControlFlowGraphNode(m_gen: full_gen, m_kill: full_kill, block: mblock)
		cfg.add_node(node)
	cfg

class ControlFlowGraph[V]:
	pub var m_nodes: List[ControlFlowGraphNode[V]] = List()

	pub fn add_node(node?: ControlFlowGraphNode[V]):
		m_nodes.append(node)

class ControlFlowGraphNode[V]:
	pub var m_gen: Set[int]
	pub var m_kill: Set[int]
	pub var m_live_in: Set[int] = new_int_set()
	pub var m_live_out: Set[int] = new_int_set()
	pub var block: mil.Block[V]

fn create_interference_graph[V](cfg: ControlFlowGraph[V]) -> InterferenceGraph:
	""" Create interference graph

	See also:
	https://en.wikipedia.org/wiki/Live-variable_analysis
	"""
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
			# TODO: include successors.
			if not old_live_in.equals(node.m_live_in) or not old_live_out.equals(node.m_live_out):
				change = true
		if not change:
			break
	log_debug("Iterations: {n_iterations}")

	let ig = InterferenceGraph()
	let reg_map = new_hashmap_int()
	for n in cfg.m_nodes:
		let block = n.block
		var live_registers: Set[int] = n.m_live_out
		var index = block.instructions.len()
		while index > 0:
			index -= 1
			let mi = block.instructions.get(index)

			let ins_kill: Set[int] = new_int_set()
			for r in mi.defs:
				ins_kill.add(r.id)
				get_ig_node(ig, reg: r)

			let ins_gen: Set[int] = new_int_set()
			for r in mi.uses:
				ins_gen.add(r.id)
				get_ig_node(ig, reg: r)

			for a in live_registers:
				let n1 = ig.add_node(a)
				# other live registers interfere:
				for b in live_registers:
					let n2 = ig.add_node(b)
					if a != b:
						ig.add_edge(n1, n2)
				# clobber registers interfere:
				for clobber in mi.clobbers:
					get_ig_node(ig, reg: clobber)
					let b = clobber.id
					let n2 = ig.add_node(b)
					if a != b:
						ig.add_edge(n1, n2)

			live_registers = ins_gen.union(live_registers.difference(ins_kill))
	ig

fn get_ig_node(ig: InterferenceGraph, reg: mil.Register):
	if not ig.has_node(reg.id):
		let n = ig.add_node(reg.id)
		n.add_reg(reg)
		if reg.color >= 0:
			n.set_color(reg.color)

class InterferenceGraph:
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

	pub fn add_node(id?: int) -> IGNode:
		if m_nodes.contains(key: id):
			m_nodes.get(key: id)
		else:
			let n = IGNode(id)
			m_nodes.insert(key: id, value: n)
			m_adj.insert(key: id, value: new_int_set())
			n

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

class IGNode:
	""" Node in the interference graph. """
	pub var id: int
	pub var color: int = -1
	pub var degree: int = 0
	pub var masked: bool = false

	var regs: List[mil.Register] = List()

	pub fn add_reg(reg: mil.Register):
		regs.append(reg)

	pub fn set_color(c?: int):
		color = c
		for reg in regs:
			reg.color = c

	pub fn is_colored() -> bool:
		color >= 0

	pub fn to_string() -> str:
		var res = "IGNode(degree={degree},regs=["
		for r in regs:
			res = res + ",R{r.id}"
		res + "])"
