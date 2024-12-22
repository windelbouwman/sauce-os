
# A graph consists of nodes and edges between them.
# There are directed and undirected graph types.

from datatypes import List, Option
from settype import new_str_set, Set
from hashmap import HashMap, new_hashmap_str

pub class DiGraph:
    # A directed graph
    var nodes: Set[str] = new_str_set()
    var pred: HashMap[str,Set[str]] = new_hashmap_str()
    var succ: HashMap[str,Set[str]] = new_hashmap_str()

    fn add_node(n?: str):
        if not nodes.contains(key: n):
            nodes.add(n)
            # TODO: assert n not in pred and succ?
            pred.insert(key: n, value: new_str_set())
            succ.insert(key: n, value: new_str_set())
    
    fn add_edge(src: str, dst: str):
        add_node(src)
        add_node(dst)
        succ.get(key: src).add(dst)
        pred.get(key: dst).add(src)
    
    fn remove_edge(src: str, dst: str):
        # Remove edge from src to dst
        succ.get(key: src).remove(dst)
        pred.get(key: dst).remove(src)

    fn has_edge(src: str, dst: str) -> bool:
        case succ.maybe_get(key: src):
            Some(s):
                s.contains(dst)
            None:
                false
    
    fn has_preds(n?: str) -> bool:
        case pred.maybe_get(key: n):
            Some(p):
                return not p.is_empty()
            None:
                false
    
    fn has_edges() -> bool:
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
