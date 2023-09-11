
# A graph consists of nodes and edges between them.
# There are directed and undirected graph types.

from std import print
from datatypes import List, Dictionary, Set, option_unwrap, Option

class DiGraph:
    # A directed graph
    var nodes: Set = Set()
    var pred: Dictionary[Set] = Dictionary()
    var succ: Dictionary[Set] = Dictionary()

    fn add_node(n?: str):
        if not this.nodes.contains(key: n):
            this.nodes.add(n)
            # TODO: assert n not in pred and succ?
            this.pred.insert(key: n, value: Set())
            this.succ.insert(key: n, value: Set())
    
    fn add_edge(src: str, dst: str):
        this.add_node(src)
        this.add_node(dst)
        option_unwrap(this.succ.get(key: src)).add(dst)
        option_unwrap(this.pred.get(key: dst)).add(src)
    
    fn remove_edge(src: str, dst: str):
        # Remove edge from src to dst
        option_unwrap(this.succ.get(key: src)).remove(dst)
        option_unwrap(this.pred.get(key: dst)).remove(src)

    fn has_edge(src: str, dst: str) -> bool:
        case this.succ.get(key: src):
            Some(s):
                return s.contains(dst)
            None:
                return false
    
    fn has_preds(n?: str) -> bool:
        case this.pred.get(key: n):
            Some(p):
                return not p.is_empty()
            None:
                return false
    
    fn has_edges() -> bool:
        for n in this.nodes:
            let pred2 = option_unwrap(this.pred.get(key: n))
            if not pred2.is_empty():
                #for p in pred2:
                #    print("{n} has pred: {p}")
                return true
        return false


#class Node:
#    var name: str = "?"

#class Edge:
#    pass


fn topological_sort(g?: DiGraph) -> Option[List[str]]:
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
        return Option.None()
    else:
        return Option.Some(result)
