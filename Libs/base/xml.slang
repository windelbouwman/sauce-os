
# XML parsing routines.

from std import str_len
from text_out import TextOut, new_text_out
from utils import unimplemented
from listtype import List
from optiontype import Option
from strlib import str_join

pub class Node:
	# An xml node!
	pub var tag: str
	pub var m_attributes: List[Attribute] = List()
	pub var m_child_nodes: List[Node] = List()
	pub var m_content: str = ""

	pub fn add_attribute(name: str, value: str):
		m_attributes.append(Attribute(name, value))

	pub fn add_child(node?: Node):
		m_child_nodes.append(node)

	pub fn add_content(text: str):
		m_content = m_content + text

struct Attribute:
	# XML attribute
	name: str
	value: str

pub fn emit_xml(node: Node, filename: Option[str]):
	let out = new_text_out(filename)
	let writer = XmlWriter(out)
	writer.write_header()
	writer.write_node(node)
	out.end()

class XmlWriter:
	var out: TextOut

	pub fn write_header():
		let attributes: List[Attribute] = List()
		attributes.append(Attribute(name: "version", value: "1.0"))
		attributes.append(Attribute(name: "encoding", value: "UTF-8"))
		# version={q}1.0{q} encoding={q}UTF-8{q}
		let attrs_text = attributes_to_string(attributes)
		emit("<?xml {attrs_text} ?>")

	pub fn write_node(node: Node):
		let attrs_text = attributes_to_string(attributes: node.m_attributes)
		if str_len(text: attrs_text) > 0:
			attrs_text = " " + attrs_text
		if node.m_child_nodes.is_empty() and str_len(text: node.m_content) == 0:
			emit("<{node.tag}{attrs_text}/>")
		else:
			emit("<{node.tag}{attrs_text}>")
			indent()
			for child_node in node.m_child_nodes:
				write_node(node: child_node)
			emit(node.m_content)
			dedent()
			emit("</{node.tag}>")

	fn attributes_to_string(attributes: List[Attribute]) -> str:
		let parts: List[str] = List()
		for attribute in attributes:
			parts.append(attribute_to_string(attribute))
		str_join(parts, sep: " ")

	fn attribute_to_string(attribute: Attribute) -> str:
		"{attribute.name}=\"{attribute.value}\""

	fn indent():
		out.indent()

	fn dedent():
		out.dedent()

	fn emit(text?: str):
		out.emit(text)

pub fn read_xml() -> Node:
	unimplemented("read_xml")

#class XmlReader:
#    pass
