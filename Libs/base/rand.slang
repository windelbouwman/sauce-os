pub class Rand:
	"""
	32 bit PCG random number generator

	Really minimal PCG32 code, ported to slang lang.
	Original C code by (c) 2014 M.E. O'Neill / pcg-random.org
	Licensed under Apache License 2.0 (NO WARRANTY, etc. see website)
	"""
	pub var state: uint64 = uint64(0)
	pub var inc: uint64 = uint64(0)

	pub fn next() -> uint32:
		"""
		Generate a random 32 bit number
		range: 0 <= x < 2**32
		"""
		let old_state = state
		state = uint64(6364136223846793005) * old_state + (inc | uint64(1))

		let xorshifted = uint32(((old_state >> uint64(18)) ^ old_state) >> uint64(27))
		let rot = uint32(old_state >> uint64(59))
		let ret = uint32((xorshifted >> rot) | (xorshifted << ((-rot) & uint32(31))))
		ret

	pub fn next_float() -> float:
		"""
		Generate a random float
		range: 0 <= x < 1
		"""
		float(next()) / float(uint64(1) << uint64(32))


