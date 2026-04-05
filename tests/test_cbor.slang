module main
"""Test CBOR"""

from std import print
from base.unittest import assert_str_equals
from base.bytes import Bytes, bytes_from_hex_text, new_bytes
from base import cbor


pub fn main() -> int:
	test_integer_encoding()
	test_negative_integer_encoding()
	test_other_encoding()
	test_bytes_encoding()
	test_string_encoding()
	test_array_encoding()
	test_map_encoding()
	test_float()
	print("OK")
	0

fn test_integer_encoding():
	let writer = cbor.CborWriter()
	writer.write_int(7)
	writer.write_int(10)
	writer.write_int(500)
	writer.write_int(23)
	writer.write_int(24)
	writer.write_int(65535)
	writer.write_int(65536)
	writer.write_int(255)
	writer.write_int(256)
	writer.write_int(1000)
	writer.write_int(1000000)
	let data = writer.finish()
	check_data_equals(data, expected: "07 0A 19 01f4 17 18 18 19 ffff 1A 00010000 18 ff 19 0100 1903e8 1a000f4240")

fn test_negative_integer_encoding():
	let writer = cbor.CborWriter()
	writer.write_int(-1)
	writer.write_int(-10)
	writer.write_int(-100)
	writer.write_int(-1000)
	let data = writer.finish()
	check_data_equals(data, expected: "20 29 3863 3903e7")

fn test_other_encoding():
	let writer = cbor.CborWriter()
	writer.write_bool(true)
	writer.write_bool(false)
	writer.write_null()
	writer.write_undefined()
	let data = writer.finish()
	check_data_equals(data, expected: "f5 f4 f6 f7")

fn test_bytes_encoding():
	let writer = cbor.CborWriter()
	writer.write_bytes(new_bytes())
	writer.write_bytes(bytes_from_hex_text(text: "01020304"))
	let data = writer.finish()
	check_data_equals(data, expected: "40 4401020304")

fn test_string_encoding():
	let writer = cbor.CborWriter()
	writer.write_string("")
	writer.write_string("a")
	writer.write_string("IETF")
	let data = writer.finish()
	check_data_equals(data, expected: "60 6161 6449455446")

fn test_array_encoding():
	let writer = cbor.CborWriter()
	# []
	writer.start_array(size: 0)

	# [1,2,3]
	writer.start_array(size: 3)
	writer.write_int(1)
	writer.write_int(2)
	writer.write_int(3)

	# [1, [2,3], [4,5]]
	writer.start_array(size: 3)
	writer.write_int(1)
	writer.start_array(size: 2)
	writer.write_int(2)
	writer.write_int(3)
	writer.start_array(size: 2)
	writer.write_int(4)
	writer.write_int(5)

	let data = writer.finish()
	check_data_equals(data, expected: "80 83010203 8301820203820405")

fn test_map_encoding():
	let writer = cbor.CborWriter()
	# {}
	writer.start_map(size: 0)

	# {1: 2, 3: 4}
	writer.start_map(size: 2)
	writer.write_int(1)
	writer.write_int(2)
	writer.write_int(3)
	writer.write_int(4)

	# {"a": 1, "b": [2,3]}
	writer.start_map(size: 2)
	writer.write_string("a")
	writer.write_int(1)
	writer.write_string("b")
	writer.start_array(size: 2)
	writer.write_int(2)
	writer.write_int(3)

	let data = writer.finish()
	check_data_equals(data, expected: "a0 a201020304 a26161016162820203")

fn test_float():
	let writer = cbor.CborWriter()
	writer.write_float(-4.1)
	writer.write_float(1.1)
	let data = writer.finish()
	check_data_equals(data, expected: "fb C010 6666 6666 6666 fb 3ff199999999999a")

fn check_data_equals(data: Bytes, expected: str):
	let expected_data = bytes_from_hex_text(text: expected)
	assert_str_equals(data.as_hex(), expected_data.as_hex())
