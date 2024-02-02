
# Idea: a canvas like API!
from utils import panic
from xml import Node

class Canvas:
    # Canvas drawing API
    var m_color: str = "black"
    var m_root: Node = Node(tag: "g")

    fn set_color(color: str):
        m_color = color

    fn draw_text(x: int, y: int, text: str):
        # Okay, lets break the text into glyphs and draw them one by one
        panic("TODO")
    
    fn draw_rect(x: int, y: int):
        panic("TODO")
    
    fn draw_line(x: int, y: int):
        # panic("TODO")
        let n = Node(tag: "line")
        n.add_attribute(name: "x1", value: "{x}")
        n.add_attribute(name: "y1", value: "{y}")
        n.add_attribute(name: "x2", value: "{x}")
        n.add_attribute(name: "y2", value: "{y}")
        n.add_attribute(name: "stroke", value: m_color)
        n.add_attribute(name: "stroke-width", value: "4")
        m_root.add_child(n)


