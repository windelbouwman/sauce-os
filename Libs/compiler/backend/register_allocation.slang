""" Register allocation

This function is machine independant.
It assigns colors to use / def registers.
"""

from logging import log_info, log_debug, log_trace
from settype import Set, new_int_set
from bitset import BitSet, new_bitset, new_small_bitset, SmallBitSet
from vectype import Vector, new_vector, new_vector_with_capacity
from deque import Queue, new_queue
from hashmap import HashMap, new_hashmap_int
from report import Report
from utils import unimplemented, panic
from listtype import List
from isel import SelectionContext, Backend, Frame
from igraph import IGNode, InterferenceGraph, create_interference_graph
import sil
import mil

pub fn reg_alloc[C,V](report: Report, backend: Backend[C,V], mfunc: mil.Function[V], frame: Frame):
	""" Implement iterated register allocation """
	log_debug("Reg-alloc {mfunc.name}")
	let r: RegisterAllocator[C,V] = RegisterAllocator:
		m_regs_by_class: backend.all_regs
		m_report: report
		m_backend: backend
		m_frame: frame
	r.alloc(mfunc)

class RegisterAllocator[C,V]:
	""" Perform graph coloring
	Take out nodes that can be colored
	When the graph is empty, place the nodes back in reverse order,
	and assign them a color
	"""
	var m_regs_by_class: Vector[Vector[int]]

	var m_ig: InterferenceGraph = InterferenceGraph(m_nodes: new_vector(), m_adj: new_vector())
	var m_select_stack: Vector[IGNode] = new_vector()
	var m_simplify_worklist: Queue[IGNode] = new_queue()
	var m_spill_worklist: HashMap[int,IGNode] = new_hashmap_int()
	var m_freeze_worklist: HashMap[int,IGNode] = new_hashmap_int()
	var m_pre_colored: HashMap[int,IGNode] = new_hashmap_int()

	var m_spill_rounds: int = 0
	var m_report: Report
	var m_backend: Backend[C,V]
	var m_frame: Frame

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
		m_ig = create_interference_graph(mfunc, vregs: m_frame.vregs)
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
				m_simplify_worklist.push(n)

	fn simplify():
		# log_debug("simplify")
		let n = m_simplify_worklist.pop()
		m_select_stack.append(n)
		m_ig.mask(n)
		for m in m_ig.adjecent(n):
			if is_colorable(m) and m_spill_worklist.contains(key: m.id):
				m_spill_worklist.drop(key: m.id)
				m_simplify_worklist.push(m)

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
			rewrite_program(mfunc, register: spill_node.reg)

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
		# TODO: not only spill i64 / f64
		let ty = if register.kind == 0:
			sil.Type.I64()
		elif register.kind == 1:
			sil.Type.F64()
		else:
			panic("Invalid class: {register.kind}")
		let value = sil.Value(id: 0, ty)
		context.set_vreg_for_value(value, register)

		# Introduce load / store operations
		for block in mfunc.blocks:
			var code_change = false
			for instruction in block.instructions:
				if instruction.is_reg_used(register):
					let load_ins = sil.Instruction(op: sil.OpCode.Load(value, address))
					m_backend.selector(ctx: m_backend.ctx, context, instruction: load_ins)
					code_change = true
				context.emit_minst(instruction)
				if instruction.is_reg_defined(register):
					let store_ins = sil.Instruction(op: sil.OpCode.Store(address, value))
					m_backend.selector(ctx: m_backend.ctx, context, instruction: store_ins)
					code_change = true
			let new_instructions = context.get_instructions()
			if code_change:
				block.instructions = new_instructions

	fn assign_colors():
		""" Assign colors """
		let all_regs_by_kind: Vector[SmallBitSet] = new_vector_with_capacity(capacity: m_regs_by_class.len())
		for regs in m_regs_by_class:
			let all_regs = new_small_bitset()
			for r in regs:
				all_regs.add(r)
			all_regs_by_kind.append(value: all_regs)

		let ok_regs = new_small_bitset()
		while not m_select_stack.is_empty():
			let n = m_select_stack.pop_last()
			m_ig.unmask(n)
			ok_regs.assign(other: all_regs_by_kind.get(index: n.reg.kind))
			for m in m_ig.adjecent(n):
				# TODO: implement register aliasing
				if n.reg.kind == m.reg.kind:
					ok_regs.remove(m.reg.color)
			if ok_regs.is_empty():
				unimplemented("Spilling")
			else:
				let reg = ok_regs.first()
				# log_debug("Color: id={n.id} kind={n.kind} {reg}")
				n.set_color(reg)

	fn is_colorable(m?: IGNode) -> bool:
		if m.is_colored():
			true
		else:
			# Use node degree. This will not work when registers alias
			# then we need to calculate num blocked.
			#let num_blocked = calculate_num_blocked(m)
			#if num_blocked != m.degree:
			# panic("Invariant violated")
			let k = m_regs_by_class.get(index: m.reg.kind).len()
			m.degree < k

	fn calculate_num_blocked(m?: IGNode) -> int:
		var x = 0
		for j in m_ig.adjecent(m):
			x += q(B: m.reg.kind, C: j.reg.kind)
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
