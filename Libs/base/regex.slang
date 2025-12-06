"""
Regex library

Based on [Brzozowski derivatives](https://en.wikipedia.org/wiki/Brzozowski_derivative).

Ported from code: [MichaelPaddon/epsilon](https://github.com/MichaelPaddon/epsilon)

"""

from std import str_get, str_len, ord, print, chr, str_slice
from integersetlib import IntegerSet, new_int_set, integer_set_from_ranges, integer_set_difference
from listtype import List, list1, list2
from optiontype import Option
from rangelib import Range, range_to_string, range_contains
from functools import map
from strlib import str_repeat
from utils import panic, assert

pub fn find(pattern: str, text: str) -> Option[Match]:
	let matches = find_all(pattern, text)
	if matches.len() > 0:
		Option.Some(matches.first())
	else:
		Option.None()

pub fn find_all(pattern: str, text: str) -> List[Match]:
	""" Find all regular expression in the given text. """
	let machine = compile(pattern)
	machine_find_all(machine, text)

pub fn find_all_text(pattern: str, text: str) -> List[str]:
	let values = find_all(pattern, text)
	map(values, function: get_text)

fn get_text(m: Match) -> str:
	m.text

pub fn split_at_pattern(text: str, pattern: str) -> List[str]:
	""" Split a string at the given regex """
	let parts: List[str] = List()
	var begin = 0
	for m in find_all(pattern, text):
		parts.append(str_slice(text, begin, end: m.begin))
		begin = m.end
	parts.append(str_slice(text, begin, end: str_len(text)))
	parts

fn machine_find_all(machine: Machine, text: str) -> List[Match]:
	let matches: List[Match] = List()

	# Matching state machine:
	var state_nr = machine.start_state
	var index = 0
	var accept = false
	var begin = 0
	var end = 0
	let n = str_len(text)
	while index < n:
		# Check if we are in an accepting state:
		if machine.accepts(state_nr):
			accept = true
			end = index

		# Determine the next state:
		let c = str_get(text, index)
		state_nr = machine.next_state(state_nr, c)
		# print("   > state={state_nr}")

		# If we are in error state, we got past valid characters.
		# Lookup last valid match (if any)
		if state_nr == machine.error_state:
			if accept:
				let part = str_slice(text, begin, end)
				matches.append(Match(begin, end, text: part))
				# Set index back to character after last match:
				index = end
			else:
				index = begin + 1

			begin = index
			state_nr = 0
			accept = false
		else:
			index += 1

	# Add last match
	if machine.accepts(state_nr):
		accept = true
		end = index
	if accept:
		let part = str_slice(text, begin, end)
		matches.append(Match(begin, end, text: part))

	matches

pub struct Match:
	begin: int
	end: int
	text: str

pub fn compile(pattern: str) -> Machine:
	# Turn regular expression into matching machine
	# print("Compiling regex: {pattern}")
	let rx = parse(pattern)
	# print_regex(rx, level: 0)
	let machine = create_machine(rx)
	# print_machine(machine)
	machine

fn create_machine(rx: Regex) -> Machine:
	# Compile regex into state machine
	# print("Creating FSM!")
	let states: List[State] = List()
	let states2: List[Regex] = List()
	let worklist: List[Regex] = List()

	worklist.append(rx)
	states2.append(rx)

	var nr = 0
	var error_state = -1
	while worklist.len() > 0:
		let rx2 = worklist.pop_front()
		# print("Considering")
		# print_regex(rx: rx2, level: 0)
		let transitions: List[Transition] = List()
		for s in rx2.derivative_classes():
			let i = s.first()
			# print("Derive to '{chr(i)}' ({i}) ")
			let rx3 = rx2.derivative(c: i)
			# print_regex(rx: rx3, level: 0)

			var to_state = contains_regex(lst: states2, rx: rx3)
			if to_state < 0:
				states2.append(rx3)
				worklist.append(rx3)
				to_state = states2.len() - 1

			# Append transitions:
			for range in s.ranges:
				transitions.append(Transition(range, to_state))
		let state = State(transitions, accepts: rx2.is_nullable())
		states.append(state)
		if rx2.is_null():
			if error_state < 0:
				error_state = nr
			else:
				panic("Multiple error states!")
		nr += 1
	let machine = Machine(states)
	machine.error_state = error_state
	machine

fn contains_regex(lst: List[Regex], rx: Regex) -> int:
	var index = 0
	for rx2 in lst:
		if rx2.equals(other: rx):
			return index
		else:
			index += 1
	-1

class Machine:
	# Regex matching machine
	pub var start_state: int = 0
	pub var error_state: int = 0
	pub var states: List[State]

	pub fn next_state(state_nr: int, c: char) -> int:
		# Given a character, what would be the next state?
		let state = states.get(index: state_nr)
		let value = ord(c)
		for transition in state.transitions:
			if range_contains(self: transition.range, value):
				return transition.to_state
		-1

	pub fn accepts(state_nr: int) -> bool:
		let state = states.get(index: state_nr)
		state.accepts

struct State:
	transitions: List[Transition]
	accepts: bool

struct Transition:
	range: Range
	to_state: int

fn parse(pattern: str) -> Regex:
	# Parse a pattern into a regex
	let p = Parser(text: pattern)
	var res = null_regex()
	try:
		res = p.parse()
	except (e: ParseError):
		panic("Error: {e.message}")
	res

pub fn print_machine(machine: Machine):
	var i = 0
	for state in machine.states:
		print("State: {i}")
		for transition in state.transitions:
			print("  {range_to_string(transition.range)} -> {transition.to_state}")
		i += 1

fn print_regex(rx: Regex, level: int):
	let txt = rx.to_string()

	let space = str_repeat(text: "    ", count: level)
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

	pub fn parse() -> Regex except ParseError:
		""" Parse a regular expression. """
		n_size = str_len(text)
		if peek() != chr(0):
			var item = parse_term()
			while peek() == '|':
				index += 1
				let item2 = parse_term()
				item = item.logical_or(other: item2)
			return item
		else:
			panic("TODO: empty regex")

	fn parse_term() -> Regex except ParseError:
		if peek() != '|' and peek() != chr(0):
			var item = parse_factor()
			while peek() != '|' and peek() != chr(0):
				let item2 = parse_factor()
				item = item.concat(other: item2)
			item
		else:
			panic("TODO: empty regex")

	fn parse_factor() -> Regex except ParseError:
		# Parse regex element, for example '[0-9]+' or 'a' or 'b+'

		# Parse base 'a', 'b' or '[0-9]'
		let c = eat()

		let res = if c == '[':
			parse_range()
		else:
			symbol_regex(c)

		# Check suffix '*' or '+' or '?'
		let c2 = peek()
		if c2 == '+':
			index += 1
			res.concat(other: res.kleene())
		elif c2 == '*':
			index += 1
			res.kleene()
		elif c2 == '?':
			index += 1
			res.logical_or(other: epsilon_regex())
		else:
			res

	fn parse_range() -> Regex except ParseError:
		""" Parse [0-9:a-z] or [^abc] """
		let invert = if peek() == '^':
			index += 1
			true
		else:
			false

		let ranges: List[Range] = List()
		while peek() != ']':
			let c1 = eat()
			let begin = ord(c1)
			if peek() == '-':
				index += 1
				let c2 = eat()
				let end = ord(c2) + 1
				if begin < end:
					ranges.append(Range(begin, end))
				else:
					raise error(message: "Invalid range: {c1}-{c2}")
			else:
				let end = begin + 1
				ranges.append(Range(begin, end))

		let c = eat()
		if c != ']':
			raise error(message: "Expected '['")
		var s = integer_set_from_ranges(ranges)
		if invert:
			s = integer_set_difference(self: sigma(), other: s)
		symbol_set_regex(s)

	fn peek() -> char:
		if index < n_size:
			str_get(text, index)
		else:
			chr(0)

	fn eat() -> char except ParseError:
		if index < n_size:
			let c = str_get(text, index)
			index += 1
			c
		else:
			raise error(message: "Cannot parse beyond input")

	fn error(message: str) -> ParseError:
		ParseError(position: index, message)

struct ParseError:
	position: int
	message: str

fn new_char_set(c: char) -> IntegerSet:
	""" Single character set """
	let begin = ord(c)
	let end = begin + 1
	new_int_set(begin, end)

fn sigma() -> IntegerSet:
	""" Return full ascii set """
	new_int_set(begin: 0, end: 256)

fn symbol_regex(c: char) -> Regex:
	""" Regex for single character """
	let s = new_char_set(c)
	symbol_set_regex(s)

fn symbol_set_regex(s: IntegerSet) -> Regex:
	Regex(kind: PartKind.Symbol(s))

fn epsilon_regex() -> Regex:
	Regex(kind: PartKind.Epsilon())

fn null_regex() -> Regex:
	Regex(kind: PartKind.Null())

pub fn sigma_regex() -> Regex:
	""" Regex with all symbols! """
	symbol_set_regex(s: sigma())

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
		r
	elif r.is_epsilon():
		r
	else:
		Regex(kind: PartKind.Kleene(r))

fn concat_regex(left: Regex, right: Regex) -> Regex:
	if left.is_null():
		left
	elif right.is_null():
		right
	elif left.is_epsilon():
		right
	elif right.is_epsilon():
		left
	else:
		Regex(kind: PartKind.Concat(left, right))

fn logical_and_regex(left: Regex, right: Regex) -> Regex:
	if left.is_null():
		left
	elif right.is_null():
		right
	else:
		Regex(kind: PartKind.LogicalAnd(left, right))

fn logical_or_regex(left: Regex, right: Regex) -> Regex:
	if left.equals(other: right):
		left
	elif left.is_null():
		right
	elif right.is_null():
		left
	else:
		Regex(kind: PartKind.LogicalOr(left, right))

fn logical_not_regex(r: Regex) -> Regex:
	Regex(kind: PartKind.LogicalNot(r))

class Regex:
	pub var kind: PartKind

	pub fn to_string() -> str:
		case kind:
			Epsilon:
				"epsilon"
			Null:
				"null"
			Kleene(r):
				"*"
			Concat(left, right):
				"Concat"
			LogicalAnd(left, right):
				"LogicalAnd"
			LogicalOr(left, right):
				"LogicalOr({left}, {right})"
			LogicalNot(r):
				"LogicalNot"
			Symbol(s):
				"Symbols({s.to_string()})"

	pub fn equals(other: Regex) -> bool:
		case kind:
			Epsilon:
				case other.kind:
					Epsilon:
						true
				else:
					false
			Null:
				case other.kind:
					Null:
						true
				else:
					false
			Kleene(r):
				case other.kind:
					Kleene(r2):
						r.equals(other: r2)
				else:
					false
			Concat(left, right):
				case other.kind:
					Concat(left2, right2):
						left.equals(other: left2) and right.equals(other: right2)
				else:
					false
			LogicalAnd(left, right):
				case other.kind:
					LogicalAnd(left2, right2):
						left.equals(other: left2) and right.equals(other: right2)
				else:
					false
			LogicalOr(left, right):
				case other.kind:
					LogicalOr(left2, right2):
						left.equals(other: left2) and right.equals(other: right2)
				else:
					false
			LogicalNot(r):
				case other.kind:
					LogicalNot(r2):
						r.equals(other: r2)
				else:
					false
			Symbol(s):
				case other.kind:
					Symbol(s2):
						s.equals(other: s2)
				else:
					false

	pub fn kleene() -> Regex:
		kleene_regex(r: this)

	pub fn concat(other: Regex) -> Regex:
		concat_regex(left: this, right: other)

	pub fn logical_and(other: Regex) -> Regex:
		logical_and_regex(left: this, right: other)

	pub fn logical_or(other: Regex) -> Regex:
		logical_or_regex(left: this, right: other)

	pub fn is_null() -> bool:
		case kind:
			Null:
				true
		else:
			false

	pub fn is_epsilon() -> bool:
		case kind:
			Epsilon:
				true
		else:
			false

	pub fn is_kleene() -> bool:
		case kind:
			Kleene(r):
				true
		else:
			false

	pub fn is_logical_not() -> bool:
		case kind:
			LogicalNot(r):
				true
		else:
			false

	pub fn derivative(c: int) -> Regex:
		# Create new regex, taking a single character.
		case kind:
			Kleene(r):
				concat_regex(left: r.derivative(c), right: this)
			Symbol(s):
				if s.contains(value: c):
					epsilon_regex()
				else:
					null_regex()
			Concat(left, right):
				let new_left = concat_regex(left: left.derivative(c), right)
				let new_right = concat_regex(left: left.nu(), right: right.derivative(c))
				logical_or_regex(left: new_left, right: new_right)
			LogicalAnd(left, right):
				logical_and_regex(left: left.derivative(c), right: right.derivative(c))
			LogicalOr(left, right):
				logical_or_regex(left: left.derivative(c), right: right.derivative(c))
			LogicalNot(r):
				logical_not_regex(r: r.derivative(c))
			Null:
				null_regex()
			Epsilon:
				null_regex()

	pub fn derivative_classes() -> List[IntegerSet]:
		# Determine character classes that are interesting
		# cases to take the derivative for.
		case kind:
			Kleene(r):
				r.derivative_classes()
			Symbol(s):
				list2(s, sigma().difference(other: s))
			Epsilon:
				list1(sigma())
			Concat(left, right):
				if left.is_nullable():
					product_intersections(left.derivative_classes(), right.derivative_classes())
				else:
					left.derivative_classes()
			Null:
				list1(sigma())
			LogicalAnd(left, right):
				product_intersections(left.derivative_classes(), right.derivative_classes())
			LogicalOr(left, right):
				product_intersections(left.derivative_classes(), right.derivative_classes())
			LogicalNot(r):
				r.derivative_classes()

	pub fn is_nullable() -> bool:
		let n = nu()
		assert(condition: n.is_epsilon() or n.is_null(), message: "nu must return null or epsilon, not {n}")
		n.is_epsilon()

	pub fn nu() -> Regex:
		# Check if this regex is nullable.
		case kind:
			Kleene(r):
				epsilon_regex()
			Symbol(s):
				null_regex()
			Epsilon:
				epsilon_regex()
			Null:
				null_regex()
			Concat(left, right):
				logical_and_regex(left: left.nu(), right: right.nu())
			LogicalAnd(left, right):
				logical_and_regex(left: left.nu(), right: right.nu())
			LogicalOr(left, right):
				logical_or_regex(left: left.nu(), right: right.nu())
			LogicalNot(r):
				let nu_r = r.nu()
				if nu_r.is_null():
					epsilon_regex()
				else:
					null_regex()


fn product_intersections(a?: List[IntegerSet], b?: List[IntegerSet]) -> List[IntegerSet]:
	# Create cartesian products, and then take union, and check for empty sets.
	# Ehm, what is this?
	let combos: List[IntegerSet] = List()
	for i in a:
		for j in b:
			let k = i.union(other: j)
			if not k.is_empty():
				combos.append(k)
	combos
