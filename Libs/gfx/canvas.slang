
# Idea: a canvas like API!
from utils import panic, log_info
from datatypes import Option
from xml import Node, emit_xml

class Canvas:
    # Canvas drawing API
    # For now, draw to SVG nodes

    var m_color: str = "black"
    var m_width: int = 1
    var m_g_node: Node = Node(tag: "g")
    var m_svg_node: Node = Node(tag: "svg")

    fn save_svg(filename: str):
        log_info("Saving chart to {filename}")
        m_svg_node.add_attribute(name: "xmlns", value: "http://www.w3.org/2000/svg")
        m_svg_node.add_child(m_g_node)
        emit_xml(node: m_svg_node, filename: Option.Some(filename))

    fn set_color(color?: str):
        m_color = color

    fn set_width(width?: int):
        m_width = width

    fn draw_text(x: int, y: int, text: str, halign: HorizontalAnchor, valign: VerticalAnchor):
        # Okay, lets break the text into glyphs and draw them one by one
        # When using SVG, we can draw text using SVG.
        let n = Node(tag: "text")
        n.add_attribute(name: "x", value: "{x}")
        n.add_attribute(name: "y", value: "{y}")
        case halign:
            Left:
                pass
            Middle:
                n.add_attribute(name: "text-anchor", value: "middle")
            Right:
                n.add_attribute(name: "text-anchor", value: "end")
        case valign:
            Top:
                n.add_attribute(name: "dominant-baseline", value: "hanging")
            Middle:
                n.add_attribute(name: "dominant-baseline", value: "middle")
            Bottom:
                pass
        n.add_content(text)
        add_node(n)
    
    fn draw_rect(x: int, y: int):
        panic("TODO")
    
    fn draw_line(x1: int, y1: int, x2: int, y2: int):
        # panic("TODO")
        let n = Node(tag: "line")
        n.add_attribute(name: "x1", value: "{x1}")
        n.add_attribute(name: "y1", value: "{y1}")
        n.add_attribute(name: "x2", value: "{x2}")
        n.add_attribute(name: "y2", value: "{y2}")
        n.add_attribute(name: "stroke", value: m_color)
        n.add_attribute(name: "stroke-width", value: "{m_width}")
        add_node(n)

    fn add_node(node?: Node):
        m_g_node.add_child(node)

enum HorizontalAnchor:
    Left
    Middle
    Right

enum VerticalAnchor:
    Top
    Middle
    Bottom
