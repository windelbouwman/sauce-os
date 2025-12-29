""" Optimize SIL program.
"""

from logging import log_info
from hashmap import HashMap, new_hashmap_str
from settype import Set, new_str_set
from vectype import Vector, new_vector_with_capacity
from deque import Queue, new_queue
import sil

pub fn opt_sil(program: sil.Program):
	for function in program.functions:
		skip_jump_blocks(function)
		opt_clean(function)

fn skip_jump_blocks(function: sil.Function):
	""" If a block contains a single jump, we can bypass that block.

	We can rewrite this:
	  jmp a
	a:
	  jmp b
	b:

	As this:
	  jmp b
	a:
	  jmp b
	b:
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
					else:
						log_info("Shortcut uppurtunutty!")
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
					log_info("Patching")
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
					log_info("Patching")
					last_instruction.op = sil.OpCode.JumpIf(lhs, condition, rhs, label1, label2)
		else:
			pass

fn opt_clean(function: sil.Function):
	""" Remove unreachable blocks. """
	# Create name -> block mapping:
	let m: HashMap[str,sil.Block] = new_hashmap_str()
	for block in function.blocks:
		m.insert(key: block.name, value: block)

	let reachable: Set[str] = new_str_set()

	# Visit all blocks
	let q: Queue[sil.Block] = new_queue()
	q.push(function.blocks[0])
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
		log_info("No block deletions")
	else:
		log_info("Unreachable blocks found!")
		let new_blocks: Vector[sil.Block] = new_vector_with_capacity(capacity: reachable.len())
		for block in function.blocks:
			if reachable.contains(key: block.name):
				new_blocks.append(block)
			else:
				log_info("Unreachable: {block.name}")
		function.blocks = new_blocks
