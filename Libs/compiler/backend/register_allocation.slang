""" Register allocation

This function is machine independant.
It assigns colors to use / def registers.
"""

from logging import log_info, log_debug, log_trace
from settype import Set, new_int_set
from hashmap import HashMap, new_hashmap_int
from report import Report
from utils import unimplemented, panic
from listtype import List
from isel import SelectionContext, Backend, Frame
from igraph import IGNode, InterferenceGraph, create_interference_graph
import sil
import mil

pub fn reg_alloc[V](report: Report, backend: Backend[V], mfunc: mil.Function[V], frame: Frame):
	""" Implement iterated register allocation """
	log_debug("Reg-alloc {mfunc.name}")
	let r: RegisterAllocator[V] = RegisterAllocator(m_report: report, m_backend: backend, m_frame: frame)
	r.add_register_class(kind: 0, regs: backend.all_regs)
	r.add_register_class(kind: 1, regs: backend.all_regs2)
	r.alloc(mfunc)

class RegisterAllocator[V]:
	""" Perform graph coloring
	Take out nodes that can be colored
	When the graph is empty, place the nodes back in reverse order,
	and assign them a color
	"""
	var m_regs_by_class: HashMap[int, List[int]] = new_hashmap_int()

	var m_ig: InterferenceGraph = InterferenceGraph()
	var m_select_stack: List[IGNode] = List()
	var m_simplify_worklist: List[IGNode] = List()
	var m_spill_worklist: HashMap[int,IGNode] = new_hashmap_int()
	var m_freeze_worklist: HashMap[int,IGNode] = new_hashmap_int()
	var m_pre_colored: HashMap[int,IGNode] = new_hashmap_int()

	var m_spill_rounds: int = 0
	var m_report: Report
	var m_backend: Backend[V]
	var m_frame: Frame

	pub fn add_register_class(kind: int, regs: List[int]):
		m_regs_by_class.insert(key: kind, value: regs)

	pub fn alloc(mfunc: mil.Function[V]):
		loop:
			fill_data(mfunc)
			loop:
				if not m_simplify_worklist.is_empty():
					simplify()
				else:
					break

			if not m_simplify_worklist.is_empty():
				panic("simplify list not empty")
			if not m_spill_worklist.is_empty():
				spill(mfunc)
				continue
				# panic("Spill list not empty")
			if not m_freeze_worklist.is_empty():
				panic("Freeze worklist not empty")
			assign_colors()
			# TODO: implement spill by re-trying the loop after code modification
			break

	fn fill_data(mfunc: mil.Function[V]):
		m_ig = create_interference_graph(mfunc)
		m_select_stack.clear()
		m_simplify_worklist.clear()
		m_spill_worklist.clear()
		m_freeze_worklist.clear()
		m_pre_colored.clear()

		for n in m_ig.nodes():
			if n.is_colored():
				m_pre_colored.insert(key: n.id, value: n)
			elif not is_colorable(n):
				m_spill_worklist.insert(key: n.id, value: n)
			elif is_move_related(n):
				m_freeze_worklist.insert(key: n.id, value: n)
			else:
				m_simplify_worklist.append(n)

	fn simplify():
		# log_debug("simplify")
		let n = m_simplify_worklist.pop_front()
		m_select_stack.append(n)
		m_ig.mask(n)
		for m in m_ig.adjecent(n):
			if is_colorable(m) and m_spill_worklist.contains(key: m.id):
				m_spill_worklist.drop(key: m.id)
				m_simplify_worklist.append(m)

	fn spill(mfunc: mil.Function[V]):
		""" Spill nodes with too many edges into memory locations. """
		m_spill_rounds += 1
		let max_spill_rounds = 2
		if m_spill_rounds > max_spill_rounds:
			panic("Give up after {max_spill_rounds} spill rounds")

		log_trace("Spilling")
		for spill_id in m_spill_worklist:
			let spill_node = m_spill_worklist.get(key: spill_id)
			log_trace("> {spill_id} = {spill_node.to_string()}")
			for register in spill_node.regs:
				rewrite_program(mfunc, register)

		m_report.heading("After rewriting spill ")
		mil.dump_mfunc(report: m_report, mfunc, to_str: m_backend.to_str)

	fn rewrite_program(mfunc: mil.Function[V], register: mil.Register):
		""" Introduce load before each use and store each definition
		"""
		m_report.writeln("Spilling {mil.vr_to_str(register)} to stack slot")
		# Create stack slot:
		let address = sil.Address.StackSlot(0) # TODO: determine proper address
		m_frame.stacksize += 8  # Grow a bit of stack size
		let context: SelectionContext[V] = SelectionContext(frame: m_frame)
		let ty = sil.Type.I64()  # TODO: not only spill integers
		let name = "y77"
		let value = sil.Value(name, ty)
		context.set_vreg_for_tmp(name, register)

		# Introduce load / store operations
		for block in mfunc.blocks:
			var code_change = false
			for instruction in block.instructions:
				if instruction.is_reg_used(register):
					let load_ins = sil.Instruction(op: sil.OpCode.Load(value, address))
					m_backend.selector(context, instruction: load_ins)
					code_change = true
				context.emit_minst(instruction)
				if instruction.is_reg_defined(register):
					let store_ins = sil.Instruction(op: sil.OpCode.Store(address, value))
					m_backend.selector(context, instruction: store_ins)
					code_change = true
			let new_instructions = context.get_instructions()
			if code_change:
				block.instructions = new_instructions

	fn assign_colors():
		""" Assign colors """
		let all_regs_by_kind: HashMap[int,Set[int]] = new_hashmap_int()
		for kind in m_regs_by_class:
			let all_regs = new_int_set()
			for r in m_regs_by_class.get(key: kind):
				all_regs.add(r)
			all_regs_by_kind.insert(key: kind, value: all_regs)

		for n in m_select_stack.reversed():
			m_ig.unmask(n)
			let taken_regs = new_int_set()
			for m in m_ig.adjecent(n):
				# TODO: implement register aliasing
				if n.kind == m.kind:
					taken_regs.add(m.color)
			let ok_regs = all_regs_by_kind.get(key: n.kind).difference(taken_regs)
			if ok_regs.is_empty():
				unimplemented("Spilling")
			else:
				let reg = ok_regs.first()
				log_debug("Color: id={n.id} kind={n.kind} {reg}")
				n.set_color(reg)

	fn is_colorable(m?: IGNode) -> bool:
		if m.is_colored():
			true
		else:
			let num_blocked = calculate_num_blocked(m)
			let k = m_regs_by_class.get(key: m.kind).len()
			num_blocked < k

	fn calculate_num_blocked(m?: IGNode) -> int:
		var x = 0
		for j in m_ig.adjecent(m):
			x += q(B: m.kind, C: j.kind)
		x

	fn q(B: int, C: int) -> int:
		""" Number of registers from class B that can be block by a register in class C. """
		# TODO: here we can support register aliasing
		if B == C:
			1 # register in same class, so we block 1 other register.
		else:
			0

	fn is_move_related(m?: IGNode) -> bool:
		false
