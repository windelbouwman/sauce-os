"""
Rope data type for modifiable text.

Idea is to store text in a binary tree. Each node has
extra meta-data. Leaf nodes contain the actual characters of
the text.

A rope data type can be used in a text editor. Inserting text
can be seen as splitting the tree, and then merging the nodes
again.
"""
from std import str_slice, str_len

pub fn new_rope(text: str) -> RopeText:
	RopeText(m_root: new_leaf_node(text))

pub class RopeText:
	var m_root: Node

	pub fn get_text() -> str:
		to_text(node: m_root)

	pub fn insert(pos: int, text: str):
		""" Insert text at the given position """
		let new_rope = new_leaf_node(text)
		if pos < m_root.size:
			let pair = split_node(node: m_root, pos)
			m_root = merge_nodes(left: pair.left, right: new_rope)
			m_root = merge_nodes(left: m_root, right: pair.right)
		elif pos == m_root.size:
			m_root = merge_nodes(left: m_root, right: new_rope)

	pub fn delete(pos: int, size: int):
		""" Delete some text """
		if pos < m_root.size:
			if size > 0:
				let pair1 = split_node(node: m_root, pos)
				let pair2 = split_node(node: pair1.right, pos: size)
				m_root = merge_nodes(left: pair1.left, right: pair2.right)

fn new_leaf_node(text: str) -> Node:
	Node:
		size: str_len(text)
		ty: NodeType.Leaf(text)

fn merge_nodes(left: Node, right: Node) -> Node:
	Node:
		size: left.size + right.size
		ty: NodeType.NonLeaf(left, right)

fn split_node(node: Node, pos: int) -> NodePair:
	case node.ty:
		Leaf(text):
			let left_text = str_slice(text, begin: 0, end: pos)
			let right_text = str_slice(text, begin: pos, end: str_len(text))
			let left = new_leaf_node(text: left_text)
			let right = new_leaf_node(text: right_text)
			NodePair(left, right)
		NonLeaf(left, right):
			if pos < left.size:
				let pair = split_node(node: left, pos)
				NodePair(left: pair.left, right: merge_nodes(left: pair.right, right))
			elif pos > left.size:
				let pair = split_node(node: right, pos: pos - left.size)
				NodePair(left: merge_nodes(left, right: pair.left), right: pair.right)
			else:
				# assert(pos == node.offset)
				NodePair(left, right)

fn to_text(node: Node) -> str:
	case node.ty:
		Leaf(text):
			text
		NonLeaf(left, right):
			to_text(node: left) + to_text(node: right)

enum NodeType:
	Leaf(text: str)
	NonLeaf(left: Node, right: Node)

struct Node:
	size: int
	# new_lines: int
	ty: NodeType

struct NodePair:
	left: Node
	right: Node
