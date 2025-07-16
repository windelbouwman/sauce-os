
from std import print
from bytes import bytes_from_ascii, bytes_from_hex_text
from unittest import assert_int_equals, assert_bytes_equals
from crypto import md5, leftrotate, compute_md5_K, fill_md5_K, sha1, sha256


pub fn main() -> int:
	test_bit_rotations()
	test_K_table()
	test_md5()
	test_sha1()
	test_sha256()
	print("OK")
	0

fn test_md5():
	# Wikipedia examples:
	check_md5(input: "", digest: "d41d8cd98f00b204e9800998ecf8427e")
	check_md5(input: "The quick brown fox jumps over the lazy dog", digest: "9e107d9d372bb6826bd81d3542a419d6")
	check_md5(input: "The quick brown fox jumps over the lazy dog.", digest: "e4d909c290d0fb1ca068ffaddf22cbd0")

	# Examples from rfc-1321:
	check_md5(input: "a", digest: "0cc175b9c0f1b6a831c399e269772661")
	check_md5(input: "abc", digest: "900150983cd24fb0d6963f7d28e17f72")
	check_md5(input: "message digest", digest: "f96b697d7cb7938d525a2f31aaf161d0")
	check_md5(input: "abcdefghijklmnopqrstuvwxyz", digest: "c3fcd3d76192e4007dfb496cca67e13b")
	check_md5(input: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", digest: "d174ab98d277d9f5a5611c2c9f419d9f")
	check_md5(input: "12345678901234567890123456789012345678901234567890123456789012345678901234567890", digest: "57edf4a22be3c955ac49da2e2107b67a")

fn test_sha1():
	# Wikipedia examples:
	check_sha1(input: "", digest: "da39a3ee5e6b4b0d3255bfef95601890afd80709")
	check_sha1(input: "The quick brown fox jumps over the lazy dog", digest: "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")
	check_sha1(input: "The quick brown fox jumps over the lazy cog", digest: "de9f2c7fd25e1b3afad3e85a0bd17d9b100db4b3")

fn test_sha256():
	# Wikipedia examples:
	check_sha256(input: "", digest: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	check_sha256(input: "abc", digest: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

fn test_K_table():
	# Compare both pre-computed and calculated K table
	let K1: [int] = [64 : int]
	let K2: [int] = [64 : int]
	compute_md5_K(K: K1)
	fill_md5_K(K: K2)
	var i = 0
	while i < 64:
		# print("i = {i} {K1[i]} == {K2[i]}")
		assert_int_equals(K1[i], K2[i])
		i += 1

fn test_bit_rotations():
	check_left_rotation(value: 0x1122, amount: 4, expected: 0x11220)
	check_left_rotation(value: 0x11223344, amount: 4, expected: 0x12233441)

fn check_left_rotation(value: int, amount: int, expected: int):
	let v2 = leftrotate(value, amount)
	assert_int_equals(v2, expected)

fn check_md5(input: str, digest: str):
	let digest2 = md5(data: bytes_from_ascii(text: input))
	assert_bytes_equals(bytes_from_hex_text(text: digest), digest2)

fn check_sha1(input: str, digest: str):
	let digest2 = sha1(data: bytes_from_ascii(text: input))
	assert_bytes_equals(bytes_from_hex_text(text: digest), digest2)

fn check_sha256(input: str, digest: str):
	let digest2 = sha256(data: bytes_from_ascii(text: input))
	assert_bytes_equals(bytes_from_hex_text(text: digest), digest2)
