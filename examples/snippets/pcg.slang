module main

from std import print

pub fn main() -> int:
	let p = PCG()
	p.seed(seed_state: uint64(42), seed_sequence: uint64(54))
	var i = 0
	while i < 5:
		i += 1
		print("round {i}: {int(p.next_int())}")
	0

class PCG:
	var state: uint64 = uint64(0)
	var inc: uint64 = uint64(0)

	pub fn seed(seed_state: uint64, seed_sequence: uint64):
		state = uint64(0)
		inc = (seed_sequence << uint64(1)) | uint64(1)
		let discard1 = next_int()
		state = state + seed_state
		let discard2 = next_int()

	pub fn next_int() -> uint32:
		let old = state
		state = old * uint64(6364136223846793005) + inc
		# print("state: {int(state)}")
		let xorshifted = uint32(((old >> uint64(18)) ^ old) >> uint64(27))
		print("xorshifted: {int(xorshifted)}")
		let rot = uint32(old >> uint64(59))
		(xorshifted >> rot) | (xorshifted << ((uint32(32) - rot) & uint32(31)))
