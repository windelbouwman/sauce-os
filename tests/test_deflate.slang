
from std import print
from unittest import assert_bytes_equals
from bytes import from_hex_text, fill_bytes
from deflate import deflate_decompress, gzip_decompress

fn main() -> int:
    test_gzip_example1()
    test_gzip_example2()
    print("OK")
    return 0

fn test_gzip_example1():
    # Data compressed using python:
    # >>> compressed = gzip.compress(bytes.fromhex('.......'))
    let compressed = from_hex_text(text: "1f8b0800f93cc26502ff6310543276094d2bef98b96af799bbeffe03009b75078410000000")
    let decompressed = gzip_decompress(compressed)
    let expected = from_hex_text(text: "00112233445566778899aabbccddeeff")
    assert_bytes_equals(decompressed, expected)

fn test_gzip_example2():
    # Data compressed using python:
    # >>> compressed = gzip.compress(bytes([0]*100))
    let compressed = from_hex_text(text: "1f8b0800e14ddb6502ff6360a03d0000cac6889964000000")
    let decompressed = gzip_decompress(compressed)
    let expected = fill_bytes(n: 100, fill: 0)
    assert_bytes_equals(decompressed, expected)
