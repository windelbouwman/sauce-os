"""
FAT filesystem implementation.

"""

from bytes import Bytes
from utils import unimplemented


class FatFs:
    var m_block_device: int = 0
    var m_sector_size: int = 0

    fn init():
        m_sector_size = 512

    fn write(filename: str):
        unimplemented("write")
    
    fn read(filename: str) -> Bytes:
        unimplemented("read")
