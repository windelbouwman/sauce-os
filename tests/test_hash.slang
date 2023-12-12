
from std import print
from unittest import assert_int_equals
from hashlib import elf_hash

fn main() -> int:
    test_hash_examples()
    print("OK")
    return 0

fn test_hash_examples():
    check_hash("jdfgsdhfsdfsd 6445dsfsd7fg/*/+bfjsdgf%$^",  248446350)
    check_hash("", 0)
    check_hash("printf", 0x077905a6)
    check_hash("exit", 0x0006cf04)
    check_hash("syscall", 0x0b09985c)
    check_hash("flapenguin.me", 0x03987915)
    check_hash("isnan", 0x0070a47e)
    check_hash("freelocal", 0x0bc334fc)
    check_hash("hcreate_", 0x0a8b8c4f)
    check_hash("getopt_long_onl", 0x0f256dbc)

fn check_hash(text?: str, value?: int):
    let x = elf_hash(text)
    assert_int_equals(x, value)
