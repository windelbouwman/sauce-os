
from std import print
from unittest import assert_bytes_equals, assert_int_equals
from bytes import bytes_from_hex_text, fill_bytes, bytes_from_ascii, Bytes
from gzip import gzip_decompress, calc_crc32
from gzip import zlib_decompress, zlib_compress, calc_adler32

fn main() -> int:
    test_gzip_example1()
    test_gzip_example2()
    test_crc32()
    test_zlib_example1()
    test_zlib_example2()
    test_adler32()
    print("OK")
    0

fn test_gzip_example1():
    # Data compressed using python:
    # >>> compressed = gzip.compress(bytes.fromhex('.......'))
    let compressed = bytes_from_hex_text(text: "1f8b0800f93cc26502ff6310543276094d2bef98b96af799bbeffe03009b75078410000000")
    let expected = bytes_from_hex_text(text: "00112233445566778899aabbccddeeff")
    let decompressed = gzip_decompress(compressed)
    assert_bytes_equals(decompressed, expected)

fn test_gzip_example2():
    # Data compressed using python:
    # >>> compressed = gzip.compress(bytes([0]*100))
    let compressed = bytes_from_hex_text(text: "1f8b0800e14ddb6502ff6360a03d0000cac6889964000000")
    let expected = fill_bytes(n: 100, fill: 0)
    let decompressed = gzip_decompress(compressed)
    assert_bytes_equals(decompressed, expected)

fn test_crc32():
    let s = "The quick brown fox jumps over the lazy dog"
    let data = bytes_from_ascii(text: s)
    let crc = calc_crc32(data)
    assert_int_equals(crc, 0x414fa339)

fn test_zlib_example1():
    # Create with python:
    # >>> compressed = zlib.compress(bytes(range(16)))
    let compressed = bytes_from_hex_text(text: "789c6360646266616563e7e0e4e2e6e1e5e3070002b80079")
    let expected = bytes_from_hex_text(text: "000102030405060708090a0b0c0d0e0f")
    let decompressed = zlib_decompress(data: compressed)
    assert_bytes_equals(decompressed, expected)

fn test_zlib_example2():
    # Created with python:
    # >>> import zlib
    # >>> compressed = zlib.compress(bytes(100))
    let compressed = bytes_from_hex_text(text: "789c6360a03d000000640001")
    let expected = fill_bytes(n: 100, fill: 0)
    let decompressed = zlib_decompress(data: compressed)
    assert_bytes_equals(decompressed, expected)

fn test_zlib_roundtrip1():
    let data = bytes_from_hex_text(text: "78")
    let compressed = zlib_compress(data)
    let decompressed = zlib_decompress(data: compressed)
    assert_bytes_equals(data, decompressed)

fn test_adler32():
    let data = bytes_from_ascii(text: "Wikipedia")
    let crc = calc_adler32(data)
    assert_int_equals(crc, 0x11E60398)

