
from math import sin, floor, fabs
from bytes import Bytes, ByteArray, ByteReader

pub fn md5(data: Bytes) -> Bytes:
	# RFC 1321
	# See also: https://en.wikipedia.org/wiki/MD5
	# And:  https://www.ietf.org/rfc/rfc1321.txt

	# Step 1: pad until almost modulo 512:
	let data2 = ByteArray()
	data2.extend(data)
	data2.append(0x80)
	while data2.len() % 64 != 56:
		data2.append(0)

	# Step 2: append length in bits
	data2.pack_u64_le(data.len() * 8)

	var a0 = 0x67452301
	var b0 = 0xefcdab89
	var c0 = 0x98badcfe
	var d0 = 0x10325476

	let s: [int] = [7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22, 5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20, 4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23, 6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21]
	var M: [int] = [16 : int]
	let K: [int] = [64 : int]
	fill_md5_K(K)

	let reader = ByteReader(m_bytes: data2.to_bytes())
	while not reader.at_end():
		var i = 0
		while i < 16:
			M[i] = reader.read_u32_le()
			i += 1

		var A = a0
		var B = b0
		var C = c0
		var D = d0

		i = 0
		while i < 64:
			var F = 0
			var g = 0
			if i < 16:
				F = (B & C) | ((0xFFffFFFF ^ B) & D)
				g = i
			elif i < 32:
				F = (D & B) | ((0xFFffFFFF ^ D) & C)
				g = (5 * i + 1) % 16
			elif i < 48:
				F = B ^ C ^ D
				g = (3 * i + 5) % 16
			else:
				F = C ^ (B | (0xFFFFFFFF ^ D))
				g = (7 * i) % 16
			F = wrap_u32(F + A + K[i] + M[g])
			A = D
			D = C
			C = B
			B = wrap_u32(B + leftrotate(value: F, amount: s[i]))

			i += 1

		a0 = wrap_u32(a0 + A)
		b0 = wrap_u32(b0 + B)
		c0 = wrap_u32(c0 + C)
		d0 = wrap_u32(d0 + D)

	let digest = ByteArray()
	digest.pack_u32_le(a0)
	digest.pack_u32_le(b0)
	digest.pack_u32_le(c0)
	digest.pack_u32_le(d0)
	digest.to_bytes()

pub fn leftrotate(value: int, amount: int) -> int:
	(0xffFFffFF & (value << amount)) | (value >> (32 - amount))

pub fn right_rotate(value: int, amount: int) -> int:
	(value >> amount) | (0xffFFffFF & (value << (32 - amount)))

pub fn right_shift(value: int, amount: int) -> int:
	value >> amount

pub fn compute_md5_K(K: [int]):
	var i = 0
	while i < 64:
		K[i] = floor(fabs(sin(i + 1)) * 0x100000000)
		i += 1

pub fn fill_md5_K(K: [int]):
	"""
	Pre computed table of
	floor(2^32 * abs(sin(i + 1)))
	"""
	K[0] = 0xd76aa478
	K[1] = 0xe8c7b756
	K[2] = 0x242070db
	K[3] = 0xc1bdceee
	K[4] = 0xf57c0faf
	K[5] = 0x4787c62a
	K[6] = 0xa8304613
	K[7] = 0xfd469501
	K[8] = 0x698098d8
	K[9] = 0x8b44f7af
	K[10] = 0xffff5bb1
	K[11] = 0x895cd7be
	K[12] = 0x6b901122
	K[13] = 0xfd987193
	K[14] = 0xa679438e
	K[15] = 0x49b40821
	K[16] = 0xf61e2562
	K[17] = 0xc040b340
	K[18] = 0x265e5a51
	K[19] = 0xe9b6c7aa
	K[20] = 0xd62f105d
	K[21] = 0x02441453
	K[22] = 0xd8a1e681
	K[23] = 0xe7d3fbc8
	K[24] = 0x21e1cde6
	K[25] = 0xc33707d6
	K[26] = 0xf4d50d87
	K[27] = 0x455a14ed
	K[28] = 0xa9e3e905
	K[29] = 0xfcefa3f8
	K[30] = 0x676f02d9
	K[31] = 0x8d2a4c8a
	K[32] = 0xfffa3942
	K[33] = 0x8771f681
	K[34] = 0x6d9d6122
	K[35] = 0xfde5380c
	K[36] = 0xa4beea44
	K[37] = 0x4bdecfa9
	K[38] = 0xf6bb4b60
	K[39] = 0xbebfbc70
	K[40] = 0x289b7ec6
	K[41] = 0xeaa127fa
	K[42] = 0xd4ef3085
	K[43] = 0x04881d05
	K[44] = 0xd9d4d039
	K[45] = 0xe6db99e5
	K[46] = 0x1fa27cf8
	K[47] = 0xc4ac5665
	K[48] = 0xf4292244
	K[49] = 0x432aff97
	K[50] = 0xab9423a7
	K[51] = 0xfc93a039
	K[52] = 0x655b59c3
	K[53] = 0x8f0ccc92
	K[54] = 0xffeff47d
	K[55] = 0x85845dd1
	K[56] = 0x6fa87e4f
	K[57] = 0xfe2ce6e0
	K[58] = 0xa3014314
	K[59] = 0x4e0811a1
	K[60] = 0xf7537e82
	K[61] = 0xbd3af235
	K[62] = 0x2ad7d2bb
	K[63] = 0xeb86d391

fn wrap_u32(value?: int) -> int:
	value & 0xFFffFFff

fn sha_pre_process(data: Bytes) -> Bytes:
	""" Append a 1 bit, and align to 512 bits. """
	# Step 1: pad until almost modulo 512:
	let data2 = ByteArray()
	data2.extend(data)
	data2.append(0x80)
	while data2.len() % 64 != 56:
		data2.append(0)

	# Step 2: append length in bits
	data2.pack_u64_be(data.len() * 8)
	data2.to_bytes()

pub fn sha1(data: Bytes) -> Bytes:
	var h0 = 0x67452301
	var h1 = 0xEFCDAB89
	var h2 = 0x98BADCFE
	var h3 = 0x10325476
	var h4 = 0xC3D2E1F0

	data = sha_pre_process(data)

	# for each chunk:
	let reader = ByteReader(m_bytes: data)
	var w = [80 : int]
	while not reader.at_end():

		var i = 0
		while i < 16:
			w[i] = reader.read_u32_be()
			i += 1
		while i < 80:
			w[i] = wrap_u32(leftrotate(value: w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], amount: 1))
			i += 1

		var a = h0
		var b = h1
		var c = h2
		var d = h3
		var e = h4

		# Main loop:
		i = 0
		while i < 80:
			var f = 0
			var k = 0
			if i < 20:
				f = (b & c) | ((0xFFffFFFF ^ b) & d)
				k = 0x5a827999
			elif i < 40:
				f = b ^ c ^ d
				k = 0x6ed9eba1
			elif i < 60:
				f = (b & c) | (b & d) | (c & d)
				k = 0x8f1bbcdc
			else:
				f = b ^ c ^ d
				k = 0xca62c1d6

			let temp = wrap_u32(leftrotate(value: a, amount: 5) + f + e + k + w[i])
			e = d
			d = c
			c = wrap_u32(leftrotate(value: b, amount: 30))
			b = a
			a = temp

			i += 1

		h0 = wrap_u32(h0 + a)
		h1 = wrap_u32(h1 + b)
		h2 = wrap_u32(h2 + c)
		h3 = wrap_u32(h3 + d)
		h4 = wrap_u32(h4 + e)

	let digest = ByteArray()
	digest.pack_u32_be(h0)
	digest.pack_u32_be(h1)
	digest.pack_u32_be(h2)
	digest.pack_u32_be(h3)
	digest.pack_u32_be(h4)
	digest.to_bytes()

pub fn sha256(data: Bytes) -> Bytes:
	""" SHA256 hash.

	See also: https://en.wikipedia.org/wiki/SHA-2
	"""
	data = sha_pre_process(data)

	var h0 = 0x6a09e667
	var h1 = 0xbb67ae85
	var h2 = 0x3c6ef372
	var h3 = 0xa54ff53a
	var h4 = 0x510e527f
	var h5 = 0x9b05688c
	var h6 = 0x1f83d9ab
	var h7 = 0x5be0cd19

	# for each chunk:
	let reader = ByteReader(m_bytes: data)
	let k = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
	var w = [64 : int]
	while not reader.at_end():

		var i = 0
		while i < 16:
			w[i] = reader.read_u32_be()
			i += 1
		while i < 64:
			let s0 = right_rotate(value: w[i-15], amount: 7) ^ right_rotate(value: w[i-15], amount: 18) ^ right_shift(value: w[i-15], amount: 3)
			let s1 = right_rotate(value: w[i-2], amount: 17) ^ right_rotate(value: w[i-2], amount: 19) ^ right_shift(value: w[i-2], amount: 10)
			w[i] = wrap_u32(w[i-16] + s0 + w[i-7] + s1)
			i += 1

		var a = h0
		var b = h1
		var c = h2
		var d = h3
		var e = h4
		var f = h5
		var g = h6
		var h = h7

		# Main loop:
		i = 0
		while i < 64:
			let s1 = right_rotate(value: e, amount: 6) ^ right_rotate(value: e, amount: 11) ^ right_rotate(value: e, amount: 25)
			let ch = (e & f) ^ ((0xffFFffFF ^ e) & g)
			let temp1 = wrap_u32(h + s1 + ch + k[i] + w[i])
			let s0 = right_rotate(value: a, amount: 2) ^ right_rotate(value: a, amount: 13) ^ right_rotate(value: a, amount: 22)
			let maj = (a & b) ^ (a & c) ^ (b & c)
			let temp2 = wrap_u32(s0 + maj)

			h = g
			g = f
			f = e
			e = wrap_u32(d + temp1)
			d = c
			c = b
			b = a
			a = wrap_u32(temp1 + temp2)

			i += 1

		h0 = wrap_u32(h0 + a)
		h1 = wrap_u32(h1 + b)
		h2 = wrap_u32(h2 + c)
		h3 = wrap_u32(h3 + d)
		h4 = wrap_u32(h4 + e)
		h5 = wrap_u32(h5 + f)
		h6 = wrap_u32(h6 + g)
		h7 = wrap_u32(h7 + h)

	let digest = ByteArray()
	digest.pack_u32_be(h0)
	digest.pack_u32_be(h1)
	digest.pack_u32_be(h2)
	digest.pack_u32_be(h3)
	digest.pack_u32_be(h4)
	digest.pack_u32_be(h5)
	digest.pack_u32_be(h6)
	digest.pack_u32_be(h7)
	digest.to_bytes()
