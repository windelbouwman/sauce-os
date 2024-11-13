
# Unique number generator
import ast

class IdGen:
    var counter: int = 1
    var m_void_type: ast.Type = ast.void_type()

    fn new_id() -> int:
        let v = counter
        counter += 1
        v
