module base.zip
"""ZIP file format."""

from logging import log_info
from fs import Path

pub fn open_archive(filename: Path) -> ZipArchive:
	log_info("Opening zip file: {filename}")
	ZipArchive()

pub class ZipArchive:
	var m_x: int = 2
