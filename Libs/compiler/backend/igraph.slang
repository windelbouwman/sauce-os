""" Interference graph.
"""

from logging import log_debug
from hashmap import HashMap, new_hashmap_int, new_hashmap_str
from vectype import Vector, new_vector, new_vector_with_capacity
from settype import Set, SetIter, new_int_set, new_str_set
from optiontype import Option
from bitset import BitSet, new_bitset, BitSetIter
from listtype import List
from strlib import str_join
from utils import panic
from report import Report
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

type LiveSet = BitSet

pub class ControlFlowGraphNode[V]:
	pub var m_gen: LiveSet
	pub var m_kill: LiveSet
	pub var m_live_in: LiveSet
	pub var m_live_out: LiveSet
	pub var block: mil.Block[V]

fn new_ig_for_vregs(vregs: Vector[mil.Register]) -> InterferenceGraph:
	let m_nodes: Vector[IGNode] = new_vector_with_capacity(capacity: vregs.len())
	let m_adj: Vector[BitSet] = new_vector_with_capacity(capacity: vregs.len())
	let N = vregs.len()
	for vreg in vregs:
		# We assume that vreg id's are exactly indici.
		# log_debug("vreg = {vreg.id}")
		let n = IGNode(id: vreg.id, kind: vreg.kind)
		n.add_reg(reg: vreg)
		if vreg.color >= 0:
			n.set_color(vreg.color)
		m_nodes.append(n)
		m_adj.append(new_bitset(n: N))
	InterferenceGraph(m_nodes, m_adj)

pub fn create_interference_graph[V](mfunc: mil.Function[V], vregs: Vector[mil.Register]) -> InterferenceGraph:
	""" Create interference graph

	See also:
	https://en.wikipedia.org/wiki/Live-variable_analysis
	"""

	let ig = new_ig_for_vregs(vregs)
	let N = vregs.len()

	let cfg: ControlFlowGraph[V] = ControlFlowGraph()
	for mblock in mfunc.blocks:
		# gen and kill sets for this block:
		var full_gen = new_bitset(n: N)
		var full_kill = new_bitset(n: N)
		for mi in mblock.instructions:
			# Register use generates a live register:
			for reg in mi.uses:
				if not full_kill.contains(reg.id):
					full_gen.add(reg.id)

			# Register definition kill live range:
			for reg in mi.defs:
				full_kill.add(reg.id)

		let node: ControlFlowGraphNode[V] = ControlFlowGraphNode:
			m_gen: full_gen
			m_kill: full_kill
			m_live_in: new_bitset(n: N)
			m_live_out: new_bitset(n: N)
			block: mblock
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

			# live out is union of all successor live in:
			node.m_live_out = new_bitset(n: N)
			for successor in cfg.get_successors(node):
				node.m_live_out.or_assign(successor.m_live_in)

			# Live in = gen | (live out - kill)
			node.m_live_in = node.m_live_out.clone()  # Copy
			node.m_live_in.andnot_assign(node.m_kill)  # difference
			node.m_live_in.or_assign(node.m_gen)  # union

			if not old_live_in.equals(node.m_live_in) or not old_live_out.equals(node.m_live_out):
				change = true
		if not change:
			break
	log_debug("Iterations: {n_iterations}")

	for n in cfg.m_nodes:
		let block = n.block
		var live_registers: LiveSet = n.m_live_out
		var index = block.instructions.len()
		while index > 0:
			index -= 1
			let mi = block.instructions.get(index)

			# defs and clobbers interfere with live registers
			for reg in mi.defs:
				add_reg_interference(ig, reg, live_registers)
			for reg in mi.clobbers:
				add_reg_interference(ig, reg, live_registers)

			# Update liveness:
			for reg in mi.defs:
				live_registers.remove(reg.id)

			for reg in mi.uses:
				live_registers.add(reg.id)
	ig

fn add_reg_interference(ig: InterferenceGraph, reg: mil.Register, live_registers: LiveSet):
	let n1 = ig.get_node(id: reg.id)
	for live in live_registers:
		if reg.id != live:
			let n2 = ig.get_node(id: live)
			ig.add_edge(n1, n2)

pub class InterferenceGraph:
	var m_nodes: Vector[IGNode]
	var m_adj: Vector[BitSet]

	pub fn mask(n?: IGNode):
		if not n.masked:
			n.masked = true
			for m_id in get_adj_set(n):
				let m = m_nodes.get(index: m_id)
				m.degree -= 1
		else:
			panic("Node already masked")

	pub fn unmask(n?: IGNode):
		if n.masked:
			n.masked = false
			for m_id in get_adj_set(n):
				let m = m_nodes.get(index: m_id)
				m.degree += 1
		else:
			panic("Node already un-masked")

	pub fn is_masked(n?: IGNode) -> bool:
		n.masked

	pub fn get_node(id: int) -> IGNode:
		m_nodes.get(index: id)

	pub fn nodes() -> Vector[IGNode]:
		m_nodes

	pub fn adjecent(n?: IGNode) -> AdjecentIter:
		""" Get a list of all non-masked neighbours """
		AdjecentIter(m_nodes, m_set_iter: get_adj_set(n).iter())

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

	fn get_adj_set(n?: IGNode) -> BitSet:
		m_adj.get(index: n.id)

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

pub class AdjecentIter:
	""" Dedicated iterator over adjecent nodes """
	var m_nodes: Vector[IGNode]
	var m_set_iter: BitSetIter

	pub fn iter() -> AdjecentIter:
		this

	pub fn next() -> Option[IGNode]:
		loop:
			case m_set_iter.next():
				Some(m_id):
					let m = m_nodes.get(index: m_id)
					if not m.masked:
						return Option.Some(m)
				None:
					break
		Option.None()

pub fn dump_ig(ig: InterferenceGraph, report: Report):
	report.heading("Interference graph")
	let nodes = ig.nodes()
	var i = 0
	while i < nodes.len():
		var j = i + 1
		while j < nodes.len():
			if ig.has_edge(ig.get_node(id: i), ig.get_node(id: j)):
				report.writeln("  {i} --- {j}")
			j += 1
		i += 1
