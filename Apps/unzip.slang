"""
Unzip app
"""

from std import print
from utils import set_log_level
from zip import open_archive

pub fn main() -> int:
	print("Unzip!")
	set_log_level(level: 2)
	let filename = "/usr/lib/jvm/java-20-openjdk/javafx-src.zip"

	let x = open_archive(filename)

	0
