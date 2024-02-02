
# XML parsing routines.

from std import print
from utils import panic
from datatypes import List
from strlib import str_join

class Node:
    # An xml node!
    var tag: str
    var m_child_nodes: List[Node] = List()
    var m_attributes: List[Attribute] = List()

    fn add_attribute(name: str, value: str):
        m_attributes.append(Attribute(name, value))

    fn add_child(node?: Node):
        m_child_nodes.append(node)

struct Attribute:
    # XML attribute
    name: str
    value: str

fn emit_xml(node: Node):
    let writer = XmlWriter()
    print("<?xml version='1.0' encoding='UTF-8'?>")
    writer.write_node(node)

class XmlWriter:
    var indent: int = 0

    fn write_node(node: Node):
        let parts: List[str] = List()
        for attribute in node.m_attributes:
            parts.append("{attribute.name}={attribute.value}")
        let attrs_text = str_join(parts, sep: " ")
        print("<{node.tag} {attrs_text}>")
        for child_node in node.m_child_nodes:
            write_node(node: child_node)
        print("</{node.tag}>")


fn read_xml() -> Node:
    panic("TODO: read_xml")

#class XmlReader:
#    pass
