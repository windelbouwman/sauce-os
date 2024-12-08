
from std import print
from bytes import bytes_from_hex_text
from utils import assert
from unittest import assert_str_equals
from gif import lzw_decode

pub fn main() -> int:
    # set_log_level(level: 5)
    test_lzw_decode()
    print("OK")
    0

fn test_lzw_decode():
    """ Test example from https://en.wikipedia.org/wiki/GIF
    00 51 FC 1B 28 70 A0 C1 83 01 01
    """
    let compressed = bytes_from_hex_text(text: "00 51 FC 1B 28 70 A0 C1 83 01 01")
    let data = lzw_decode(data: compressed)
    let expected = bytes_from_hex_text(text: "28 FF FF FF 28 FF FF FF FF FF FF FF FF FF FF")
    assert(condition: expected.len() == 15, message: "Example image is 3x5 pixels")
    assert_str_equals(data.as_hex(), expected.as_hex())
