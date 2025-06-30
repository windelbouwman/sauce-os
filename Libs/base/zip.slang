""" ZIP file format.
"""

from utils import log_info

pub fn open_archive(filename: str) -> ZipArchive:
	log_info("Opening zip file: {filename}")
	ZipArchive()

pub class ZipArchive:
	var m_x: int = 2
