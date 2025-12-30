""" Optimize SIL program.
"""

from logging import log_info
from utils import panic
from hashmap import HashMap, new_hashmap_str
from settype import Set, new_str_set
from vectype import Vector, new_vector_with_capacity
from deque import Queue, new_queue
import sil

pub fn optimize_sil(program: sil.Program, level: int):
	if level == 0:
		return
	log_info("Optimizing SIL code")
	for function in program.functions:
		optimize_function(function)

fn optimize_function(function: sil.Function):
	# Create name -> block mapping:
	let m: HashMap[str,sil.Block] = new_hashmap_str()
	for block in function.blocks:
		m.insert(key: block.name, value: block)

	# Iterate until fixed point:
	var changes = true
	while changes:
		changes = false
		if skip_jump_blocks(function):
			changes = true
		if block_fusion(function, m):
			changes = true
		if opt_clean(function, m):
			changes = true

pub fn skip_jump_blocks(function: sil.Function) -> bool:
	""" If a block contains a single jump, we can bypass that block.

	We can rewrite this:
	  jmp foo
	...
	foo:
	  jmp bar
	...
	bar:

	To this:
	  jmp bar
	...
	bar:
	"""

	let shotcuts: HashMap[str,str] = new_hashmap_str()

	# Find shortcuts:
	for block in function.blocks:
		# if only instruction is a jump, we can skip this useless block fast forward
		if block.instructions.len() == 1:
			case block.instructions[0].op:
				Jump(target):
					# Prevent loops:
					if shotcuts.contains(key: target) or block.name == target:
						# Possible loop
						log_info("Possible loop")
					elif block.name == function.start.name:
						# Skip the start block
						# panic("Do not remove start block.")
						pass
					else:
						# log_info("Shortcut uppurtunutty!")
						shotcuts.insert(key: block.name, value: target)
			else:
				pass

	# Apply shortcuts:
	for block in function.blocks:
		let last_instruction = block.instructions.last()
		case last_instruction.op:
			Jump(target):
				var update = false
				while shotcuts.contains(key: target):
					target = shotcuts.get(key: target)
					update = true
				if update:
					# log_info("Patching")
					last_instruction.op = sil.OpCode.Jump(target)
			JumpIf(lhs, condition, rhs, label1, label2):
				var update = false
				while shotcuts.contains(key: label1):
					label1 = shotcuts.get(key: label1)
					update = true
				while shotcuts.contains(key: label2):
					label2 = shotcuts.get(key: label2)
					update = true
				if update:
					# log_info("Patching")
					last_instruction.op = sil.OpCode.JumpIf(lhs, condition, rhs, label1, label2)
		else:
			pass

	# Remove short-circuited blocks:
	if shotcuts.is_empty():
		false
	else:
		let new_blocks: Vector[sil.Block] = new_vector_with_capacity(capacity: function.blocks.len() - shotcuts.len())
		for block in function.blocks:
			if not shotcuts.contains(key: block.name):
				new_blocks.append(block)
		function.blocks = new_blocks
		true

fn block_fusion(function: sil.Function, m: HashMap[str,sil.Block]) -> bool:
	""" Combine blocks, if possible.

	Criteria:
	- block B must have only a single predecessor: block A
	"""
	# Count number of predecessors per block:
	let pred_count: HashMap[str,int] = new_hashmap_str()

	# Implicit entry to start block:
	inc_pred(pred_count, target: function.start.name)
	for block in function.blocks:
		let last_instruction = block.instructions.last()
		case last_instruction.op:
			Jump(target):
				inc_pred(pred_count, target)
			JumpIf(lhs, condition, rhs, label1, label2):
				inc_pred(pred_count, target: label1)
				inc_pred(pred_count, target: label2)
		else:
			pass

	# Merge blocks
	let removed: Set[str] = new_str_set()
	for block in function.blocks:
		if not removed.contains(key: block.name):
			var g = true
			while g:
				g = false
				let last_instruction = block.instructions.last()
				case last_instruction.op:
					Jump(target):
						let n_preds = pred_count.get(key: target)
						if n_preds == 1 and not (target == function.start.name):
							# We may glue!
							# log_info("We may glue {block.name} and {target}!")
							let succ = m.get(key: target)
							let removed_jump = block.instructions.pop_last()
							block.instructions.extend(other: succ.instructions)
							removed.add(target)
							g = true
						# else:
						# 	log_info("Not merging: {block.name}, {target} has {n_preds} predecessors")
				else:
					pass

	# Remove merged blocks:
	if removed.is_empty():
		false
	else:
		let new_blocks: Vector[sil.Block] = new_vector_with_capacity(capacity: function.blocks.len() - removed.len())
		for block in function.blocks:
			if not removed.contains(key: block.name):
				new_blocks.append(block)
		function.blocks = new_blocks
		true

fn inc_pred(pred_count: HashMap[str,int], target: str):
	let value = if pred_count.contains(key: target):
		let old_value = pred_count.get(key: target)
		old_value + 1
	else:
		1
	pred_count.insert(key: target, value)

fn opt_clean(function: sil.Function, m: HashMap[str,sil.Block]) -> bool:
	""" Remove unreachable blocks. """
	let reachable: Set[str] = new_str_set()

	# Visit all blocks
	let q: Queue[sil.Block] = new_queue()
	q.push(function.start)
	while not q.is_empty():
		let block = q.pop()
		reachable.add(block.name)

		let last_instruction = block.instructions.last()
		case last_instruction.op:
			Jump(target):
				if not reachable.contains(target):
					q.push(m.get(key: target))
			JumpIf(lhs, condition, rhs, label1, label2):
				if not reachable.contains(label1):
					q.push(m.get(key: label1))
				if not reachable.contains(label2):
					q.push(m.get(key: label2))
		else:
			pass

	if function.blocks.len() == reachable.len():
		false
	else:
		log_info("Unreachable blocks found!")
		let new_blocks: Vector[sil.Block] = new_vector_with_capacity(capacity: reachable.len())
		for block in function.blocks:
			if reachable.contains(key: block.name):
				new_blocks.append(block)
			else:
				log_info("Unreachable: {block.name}")
		function.blocks = new_blocks
		true
