"""
A graph consists of nodes and edges between them.
There are directed and undirected graph types.
"""

from datatypes import List, Option
from settype import new_str_set, Set
from hashmap import HashMap, new_hashmap_str

pub class DiGraph:
	""" A directed graph """
	pub var nodes: Set[str] = new_str_set()
	var pred: HashMap[str,Set[str]] = new_hashmap_str()
	var succ: HashMap[str,Set[str]] = new_hashmap_str()

	pub fn add_node(n?: str):
		if not nodes.contains(key: n):
			nodes.add(n)
			# TODO: assert n not in pred and succ?
			pred.insert(key: n, value: new_str_set())
			succ.insert(key: n, value: new_str_set())
	
	pub fn add_edge(src: str, dst: str):
		add_node(src)
		add_node(dst)
		succ.get(key: src).add(dst)
		pred.get(key: dst).add(src)
	
	pub fn remove_edge(src: str, dst: str):
		# Remove edge from src to dst
		succ.get(key: src).remove(dst)
		pred.get(key: dst).remove(src)

	pub fn has_edge(src: str, dst: str) -> bool:
		case succ.maybe_get(key: src):
			Some(s):
				s.contains(dst)
			None:
				false
	
	pub fn successors(n?: str) -> Set[str]:
		succ.get(key: n)

	pub fn has_preds(n?: str) -> bool:
		case pred.maybe_get(key: n):
			Some(p):
				return not p.is_empty()
			None:
				false
	
	pub fn has_edges() -> bool:
		for n in nodes:
			let pred2 = pred.get(key: n)
			if not pred2.is_empty():
				#for p in pred2:
				#    print("{n} has pred: {p}")
				return true
		false

pub fn topological_sort(g?: DiGraph) -> Option[List[str]]:
	# Destroys the graph!

	# Kahn's algorithm
	# See: https://en.wikipedia.org/wiki/Topological_sorting#Kahn's_algorithm
	let result: List[str] = List()
	let S: List[str] = List()

	for n1 in g.nodes:
		if not g.has_preds(n1):
			S.append(n1)
	
	while not S.is_empty():
		let n2 = S.pop_front()
		result.append(n2)
		for n3 in g.nodes:
			if g.has_edge(src: n2, dst: n3):
				g.remove_edge(src: n2, dst: n3)
				if not g.has_preds(n3):
					S.append(n3)
	
	if g.has_edges():
		# We detected a dependency cycle
		Option.None()
	else:
		Option.Some(result)

pub class Graph:
	""" Undirected graph """
	pub var m_nodes: Set[str] = new_str_set()
	var m_neighbours: HashMap[str,Set[str]] = new_hashmap_str()

	pub fn add_node(n?: str):
		if not m_nodes.contains(key: n):
			m_nodes.add(n)
			m_neighbours.insert(key: n, value: new_str_set())

	pub fn add_edge(src?: str, dst?: str):
		add_node(src)
		add_node(dst)
		m_neighbours.get(key: src).add(dst)
		m_neighbours.get(key: dst).add(src)
	
	pub fn has_edge(src?: str, dst?: str) -> bool:
		if m_neighbours.contains(key: src):
			m_neighbours.get(key: src).contains(key: dst)
		else:
			false
	
	pub fn neighbours(n?: str) -> Set[str]:
		m_neighbours.get(key: n)

pub fn find_max_cliques(g: Graph) -> List[Set[str]]:
	""" Find maximum cliques with the Bron Kerbosch algorithm """
	let output: List[Set[str]] = List()
	bron_kerbosch(r: new_str_set(), p: g.m_nodes, x: new_str_set(), g, output)
	output

fn bron_kerbosch(r: Set[str], p: Set[str], x: Set[str], g: Graph, output: List[Set[str]]):
	""" An algorithm for solving the clique problem:
	https://en.wikipedia.org/wiki/Bron%E2%80%93Kerbosch_algorithm
	"""
	if p.is_empty() and x.is_empty():
		output.append(r)
	
	for v in p:
		let n = g.neighbours(v)
		let v_set = new_str_set()
		v_set.add(v)
		bron_kerbosch(r: r.union(other: v_set), p: p.intersection(other: n), x: x.intersection(other: n), g, output)
		p = p.difference(other: v_set)
		x = x.union(other: v_set)

pub fn find_all_cliques_of_size(g: Graph, k: int) -> List[Set[str]]:
	let output: List[Set[str]] = List()
	bron_kerbosch_k(r: new_str_set(), p: g.m_nodes, x: new_str_set(), g, k, output)
	output

fn bron_kerbosch_k(r: Set[str], p: Set[str], x: Set[str], g: Graph, k: int, output: List[Set[str]]):
	""" A mutated Bron Kerbosch algorithm
	"""
	if r.len() == k:
		output.append(r)
		return

	for v in p:
		let n = g.neighbours(v)
		let v_set = new_str_set()
		v_set.add(v)
		bron_kerbosch_k(r: r.union(other: v_set), p: p.intersection(other: n), x: x.intersection(other: n), g, k, output)
		p = p.difference(other: v_set)
		x = x.union(other: v_set)
