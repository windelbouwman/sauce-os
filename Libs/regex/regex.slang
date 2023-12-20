
# Regex library

from std import str_get, str_len, ord, print, chr
from integersetlib import IntegerSet, new_int_set
from datatypes import List, vec1, vec2, vec3
from rangelib import Range, range_to_string
from strlib import str_repeat
from utils import panic, assert

fn compile(text: str) -> Machine:
    # Turn regular expression into matching machine
    print("Compiling regex: {text}")
    let rx = parse(text)
    print_regex(rx, level: 0)
    let machine = create_machine(rx)
    print_machine(machine)
    return machine

fn create_machine(rx: Regex) -> Machine:
    # Compile regex into state machine
    print("Creating FSM!")
    let states: List[State] = List()

    let states2: List[Regex] = List()
    states2.append(rx)

    let worklist: List[Regex] = List()
    worklist.append(rx)

    # let chars: List[int] = vec3(ord('0'), ord('a'), ord('b'))
    while worklist.len() > 0:
        let rx2 = worklist.pop_front()
        print("Considering")
        print_regex(rx: rx2, level: 0)
        let transitions: List[Transition] = List()
        for s in rx2.derivative_classes():
            let i = s.first()
            print("Derive to '{chr(i)}' ({i}) ")
            let rx3 = rx2.derivative(c: i)
            print_regex(rx: rx3, level: 0)
            
            let to_state = contains_regex(lst: states2, rx: rx3)
            if to_state < 0:
                states2.append(rx3)
                worklist.append(rx3)
                to_state = states2.len()
            
            # Append transitions:
            for range in s.ranges:
                transitions.append(Transition(range, to_state))
        states.append(State(transitions))
    return Machine(states)

fn contains_regex(lst: List[Regex], rx: Regex) -> int:
    let index = 0
    for rx2 in lst:
        if rx2.equals(other: rx):
            return index
        else:
            index += 1
    return -1

class Machine:
    # Regex matching machine
    var states: List[State]

struct State:
    transitions: List[Transition]

struct Transition:
    range: Range
    to_state: int

fn parse(text: str) -> Regex:
    let p = Parser(text)
    return p.parse()

fn print_machine(machine: Machine):
    let i = 0
    for state in machine.states:
        print("State: {i}")
        for transition in state.transitions:
            print("  {range_to_string(transition.range)} -> {transition.to_state}")
        i += 1

fn print_regex(rx: Regex, level: int):
    let txt = rx.to_string()
        
    let space = str_repeat(text: " ", count: level * 4)
    print("{space}RE: {txt}")
    level += 1
    case rx.kind:
        Epsilon:
            pass
        Null:
            pass
        Kleene(r):
            print_regex(rx: r, level)
        Concat(a, b):
            print_regex(rx: a, level)
            print_regex(rx: b, level)
        LogicalAnd(left, right):
            print_regex(rx: left, level)
            print_regex(rx: right, level)
        LogicalOr(left, right):
            print_regex(rx: left, level)
            print_regex(rx: right, level)
        LogicalNot(r):
            print_regex(rx: r, level)
        Symbol(s):
            pass

class Parser:
    var index: int = 0
    var n_size: int = 0
    var text: str

    fn parse() -> Regex:
        # Parse a regular expression.
        n_size = str_len(text)
        if index < n_size:
            let item = parse_item()
            while index < n_size:
                let item2 = parse_item()
                item = item.concat(other: item2)
            return item
        else:
            panic("TODO: empty regex")

    fn parse_item() -> Regex:
        # Parse regex element, for example '[0-9]+' or 'a' or 'b+'

        # Parse base 'a', 'b' or '[0-9]'
        assert(condition: index < n_size, message: "Cannot parse beyond string length")
        let c = str_get(text, index)
        index += 1

        let res = null_regex()
        if c == '[':
            let s = parse_range()
            loop:
                c = str_get(text, index)
                if c == ']':
                    index += 1
                    break
                else:
                    panic("TODO!")
            res = symbol_set_regex(s)
        else:
            res = symbol_regex(c)

        # Check suffix '*' or '+'
        if index < n_size:
            let c2 = str_get(text, index)
            if c2 == '+':
                # '+' suffix, one or more
                index += 1
                res = res.concat(other: res.kleene())
            elif c2 == '*':
                # '*' suffix, zero or more, kleene star
                index += 1
                res = res.kleene()

        return res

    fn parse_range() -> IntegerSet:
        assert(condition: index < n_size, message: "Cannot parse beyond input")
        let c1 = str_get(text, index)
        index += 1

        # Assume [0-9] for now
        assert(condition: index < n_size, message: "Cannot parse beyond input")
        let c2 = str_get(text, index)
        index += 1
        # assume '-' for now.

        assert(condition: index < n_size, message: "Cannot parse beyond input")
        let c3 = str_get(text, index)
        index += 1

        # panic("TODO!")
        return new_char_set2(c1, c2: c3)


fn new_char_set(c: char) -> IntegerSet:
    # Single character set
    let begin = ord(c)
    let end = begin + 1
    return new_int_set(begin, end)

fn new_char_set2(c1: char, c2: char) -> IntegerSet:
    # Range of characters
    let begin = ord(c1)
    let end = ord(c2) + 1
    return new_int_set(begin, end)

fn sigma() -> IntegerSet:
    # Return full ascii set
    return new_int_set(begin: 0, end: 256)

fn symbol_regex(c: char) -> Regex:
    # Regex for single character
    let s = new_char_set(c)
    return symbol_set_regex(s)

fn symbol_set_regex(s: IntegerSet) -> Regex:
    # Regex for single character
    return Regex(kind: PartKind.Symbol(s))

fn epsilon_regex() -> Regex:
    return Regex(kind: PartKind.Epsilon())

fn null_regex() -> Regex:
    return Regex(kind: PartKind.Null())

fn sigma_regex() -> Regex:
    # Regex with all symbols!
    return symbol_set_regex(s: sigma())

enum PartKind:
    Kleene(r: Regex)
    Symbol(s: IntegerSet)
    Concat(left: Regex, right: Regex)
    LogicalAnd(left: Regex, right: Regex)
    LogicalOr(left: Regex, right: Regex)
    LogicalNot(r: Regex)
    Null
    Epsilon

fn kleene_regex(r: Regex) -> Regex:
    if r.is_kleene():
        return r
    elif r.is_epsilon():
        return r
    return Regex(kind: PartKind.Kleene(r))

fn concat_regex(left: Regex, right: Regex) -> Regex:
    if left.is_null():
        return left
    elif right.is_null():
        return right
    elif left.is_epsilon():
        return right
    elif right.is_epsilon():
        return left

    return Regex(kind: PartKind.Concat(left, right))

fn logical_and_regex(left: Regex, right: Regex) -> Regex:
    if left.is_null():
        return left
    return Regex(kind: PartKind.LogicalAnd(left, right))

fn logical_or_regex(left: Regex, right: Regex) -> Regex:
    if left.is_null():
        return right
    elif right.is_null():
        return left
    return Regex(kind: PartKind.LogicalOr(left, right))

fn logical_not_regex(r: Regex) -> Regex:
    return Regex(kind: PartKind.LogicalNot(r))

class Regex:
    var kind: PartKind

    fn to_string() -> str:
        let txt = "?"
        case kind:
            Epsilon:
                txt = "epsilon"
            Null:
                txt = "null"
            Kleene(r):
                txt = "*"
            Concat(left, right):
                txt = "Concat"
            LogicalAnd(left, right):
                txt = "LogicalAnd"
            LogicalOr(left, right):
                txt = "LogicalOr"
            LogicalNot(r):
                txt = "LogicalNot"
            Symbol(s):
                txt = "Symbols({s.to_string()})"
        return txt
    
    fn equals(other: Regex) -> bool:
        case kind:
            Epsilon:
                case other.kind:
                    Epsilon:
                        return true
                else:
                    return false
            Null:
                case other.kind:
                    Null:
                        return true
                else:
                    return false
            Kleene(r):
                case other.kind:
                    Kleene(r2):
                        return r.equals(other: r2)
                else:
                    return false
            Concat(left, right):
                case other.kind:
                    Concat(left2, right2):
                        return left.equals(other: left2) and right.equals(other: right2)
                else:
                    return false
            LogicalAnd(left, right):
                case other.kind:
                    LogicalAnd(left2, right2):
                        return left.equals(other: left2) and right.equals(other: right2)
                else:
                    return false
            LogicalOr(left, right):
                case other.kind:
                    LogicalOr(left2, right2):
                        return left.equals(other: left2) and right.equals(other: right2)
                else:
                    return false
            LogicalNot(r):
                case other.kind:
                    LogicalNot(r2):
                        return r.equals(other: r2)
                else:
                    return false
            Symbol(s):
                case other.kind:
                    Symbol(s2):
                        return s.equals(other: s2)
                else:
                    return false

    fn kleene() -> Regex:
        return kleene_regex(r: this)

    fn concat(other: Regex) -> Regex:
        return concat_regex(left: this, right: other)

    fn logical_and(other: Regex) -> Regex:
        return logical_and_regex(left: this, right: other)

    fn logical_or(other: Regex) -> Regex:
        return logical_or_regex(left: this, right: other)
    
    fn is_null() -> bool:
        case kind:
            Null:
                return true
        else:
            return false

    fn is_epsilon() -> bool:
        case kind:
            Epsilon:
                return true
        else:
            return false

    fn is_kleene() -> bool:
        case kind:
            Kleene(r):
                return true
        else:
            return false

    fn is_logical_not() -> bool:
        case kind:
            LogicalNot(r):
                return true
        else:
            return false

    fn derivative(c: int) -> Regex:
        # Create new regex, taking a single character.
        case kind:
            Kleene(r):
                return concat_regex(left: r.derivative(c), right: this)
            Symbol(s):
                if s.contains(value: c):
                    return epsilon_regex()
                else:
                    return null_regex()
            Concat(left, right):
                let new_left = concat_regex(left: left.derivative(c), right)
                let new_right = concat_regex(left: left.nu(), right: right.derivative(c))
                return logical_or_regex(left: new_left, right: new_right)
            LogicalAnd(left, right):
                return logical_and_regex(left: left.derivative(c), right: right.derivative(c))
            LogicalOr(left, right):
                return logical_or_regex(left: left.derivative(c), right: right.derivative(c))
            LogicalNot(r):
                return logical_not_regex(r: r.derivative(c))
            Null:
                return null_regex()
            Epsilon:
                return null_regex()
    
    fn derivative_classes() -> List[IntegerSet]:
        # Determine character classes that are interesting
        # cases to take the derivative for.
        case kind:
            Kleene(r):
                return r.derivative_classes()
            Symbol(s):
                return vec2(s, sigma().difference(other: s))
            Epsilon:
                return vec1(sigma())
            Concat(left, right):
                if left.is_nullable():
                    return product_intersections(left.derivative_classes(), right.derivative_classes())
                else:
                    return left.derivative_classes()
            Null:
                return vec1(sigma())
            LogicalAnd(left, right):
                return product_intersections(left.derivative_classes(), right.derivative_classes())
            LogicalOr(left, right):
                return product_intersections(left.derivative_classes(), right.derivative_classes())
            LogicalNot(r):
                return r.derivative_classes()

    fn is_nullable() -> bool:
        let n = nu()
        assert(condition: n.is_epsilon() or n.is_null(), message: "nu must return null or epsilon")
        return n.is_epsilon()

    fn nu() -> Regex:
        # Check if this regex is nullable.
        case kind:
            Kleene(r):
                return epsilon_regex()
            Symbol(s):
                return null_regex()
            Epsilon:
                return epsilon_regex()
            Null:
                return null_regex()
            Concat(left, right):
                return logical_and_regex(left: left.nu(), right: right.nu())
            LogicalAnd(left, right):
                return logical_and_regex(left: left.nu(), right: right.nu())
            LogicalOr(left, right):
                return logical_or_regex(left: left.nu(), right: right.nu())
            LogicalNot(r):
                let nu_r = r.nu()
                if nu_r.is_null():
                    return epsilon_regex()
                else:
                    return null_regex()


fn product_intersections(a?: List[IntegerSet], b?: List[IntegerSet]) -> List[IntegerSet]:
    # Create cartesian products, and then take union, and check for empty sets.
    # Ehm, what is this?
    let combos = List()
    for i in a:
        for j in b:
            let k = i.union(other: j)
            if not k.is_empty():
                combos.append(k)
    return combos
