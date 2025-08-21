"""
ELF file format
"""

import std
from bytes import Bytes, ByteArray, new_bytes, bytes_from_ascii
from utils import assert, log_error, log_info

# TODO: support global constants:
# let SHT_NULL = 0
# let SHT_PROGBITS = 1
# let SHT_SYMTAB = 2
# let SHT_STRTAB = 3
# let SHT_RELA = 4

pub fn write_elf(filename: str, code: Bytes):
	""" Write ELF file."""
	log_info("Writing elf file: {filename}")
	let handle = std.file_open(filename, mode: "wb")
	let writer = ElfWriter(handle)

	# Skip over header, will be patched later.
	writer.seek(pos: writer.m_header.e_ehsize)

	let string_table = StringTable()
	let sh_null = new_sh()
	sh_null.sh_name = string_table.add_name("")

	# TODO: write eventual program headers here

	# .text section
	let sh_text = new_sh()
	sh_text.sh_name = string_table.add_name(".text")
	sh_text.sh_type = 1 # PROGBITS
	sh_text.sh_flags = 2 | 4  # ALLOC | EXECINSTR
	sh_text.sh_offset = writer.tell()
	sh_text.sh_addralign = 1
	writer.write_bytes(code)
	sh_text.sh_size = writer.tell() - sh_text.sh_offset

	# section header string table
	let sh_shstrtab = new_sh()
	sh_shstrtab.sh_name = string_table.add_name(".shstrtab")
	sh_shstrtab.sh_type = 3 # SHT_STRTAB
	sh_shstrtab.sh_offset = writer.tell()
	sh_shstrtab.sh_addralign = 1
	writer.write_bytes(string_table.get_data())
	sh_shstrtab.sh_size = writer.tell() - sh_shstrtab.sh_offset

	# Write section headers now:
	writer.write_section_header(sh_null)
	writer.write_section_header(sh_text)
	writer.m_header.e_shstrndx = writer.m_header.e_shnum
	writer.write_section_header(sh_shstrtab)

	# Write header:
	writer.seek(pos: 0)
	writer.write_header()  # Write final header again

	std.file_close(handle)

pub fn read_elf(filename: str):
	let handle = std.file_open(filename, mode: "rb")
	let reader = ElfReader(handle)
	try:
		let header = reader.read_header()
	except (err : str):
		log_error("Error reading ELF file: {err}")
	std.file_close(handle)

fn new_64bit_header() -> ElfHeader:
	let header = ElfHeader:
		e_type: 3  # 2=exec, 3=dynamic
		e_machine: 0x3e  # 0x3E = x86-64
		e_entry: 0
		e_phoff: 0
		e_shoff: 0
		e_flags: 0
		e_ehsize: 64  # size of the elf header
		e_phentsize: 0  # typically 0x38
		e_phnum: 0
		e_shentsize: 0  # typically 64
		e_shnum: 0
		e_shstrndx: 0

	header

fn new_sh() -> SectionHeader:
	SectionHeader:
		sh_name: 0
		sh_type: 0
		sh_flags: 0
		sh_addr: 0
		sh_offset: 0
		sh_size: 0
		sh_link: 0
		sh_info: 0
		sh_addralign: 0
		sh_entsize: 0

struct ElfHeader:
	e_type: int
	e_machine: int
	e_entry: int  # Entry point
	e_phoff: int  # Program header offset
	e_shoff: int  # Section header offset
	e_flags: int  # architecture depending flags
	e_ehsize: int
	e_phentsize: int  # size of program header entry
	e_phnum: int  # Number of program header entries
	e_shentsize: int
	e_shnum: int  # Number of sections
	e_shstrndx: int  # Index of section with section names

struct ProgramHeader:
	p_type: int
	p_flags: int
	p_offset: int
	p_vaddr: int
	p_paddr: int
	p_filesz: int
	p_memsz: int
	p_align: int

struct SectionHeader:
	sh_name: int  # Offset into shstrtab that gives this name
	sh_type: int  # 0=NULL,1=PROGBITS
	sh_flags: int
	sh_addr: int
	sh_offset: int
	sh_size: int
	sh_link: int
	sh_info: int
	sh_addralign: int
	sh_entsize: int

class ElfReader:
	var handle: int
	var is_32bit: bool = false
	var is_big_endian: bool = false

	pub fn read_header() -> ElfHeader except str:
		# Read 16 bytes
		let e_ident = read_bytes(n: 16)
		if e_ident[0] != 0x7F or e_ident[1] != 0x45 or e_ident[2] != 0x4c or e_ident[3] != 0x46:
			raise "Invalid ELF magic"
		let ei_class = e_ident[4]
		if ei_class == 1:
			is_32bit = true
		elif ei_class == 2:
			is_32bit = false
		else:
			raise "Invalid EI_CLASS"
		let ei_data = e_ident[5]
		if ei_data == 1:
			is_big_endian = false
		elif ei_data == 2:
			is_big_endian = true
		else:
			raise "Invalid EI_DATA"
		let e_type = read16() # 0-2
		let e_machine = read16() # 2-4
		let e_version = read32() # 4-8
		let e_entry = read64() # 8-16
		let e_phoff = read64() # 16-24
		let e_shoff = read64() # 24-32
		let e_flags = read32() # 32-36
		let e_ehsize = read16() # 36-38
		let e_phentsize = read16() # 38-40
		let e_phnum = read16() # 40-42
		let e_shentsize = read16() # 42-44
		let e_shnum = read16() # 44-46
		let e_shstrndx = read16() # 46-48
		ElfHeader:
			e_type
			e_machine
			e_entry
			e_phoff
			e_shoff
			e_flags
			e_ehsize
			e_phentsize
			e_phnum
			e_shentsize
			e_shnum
			e_shstrndx

	fn read_bytes(n: int) -> Bytes:
		new_bytes()

	fn read64() -> int:
		0

	fn read32() -> int:
		0

	fn read16() -> int:
		0

class ElfWriter:
	var handle: int
	var is_32bit: bool = false
	var is_big_endian: bool = false
	pub var m_header: ElfHeader = new_64bit_header()

	pub fn write_header():
		write_array([0x7F, 0x45, 0x4c, 0x46], size: 4)  # EI_MAG
		# 1=32 bit, 2=64 bit
		let ei_class = 1 if is_32bit else 2
		# EI_DATA 1 = little endian, 2 = big endian
		let ei_data = 2 if is_big_endian else 1
		write8(ei_class)  # EI_CLASS 1 = 32 bit, 2 = 64 bit
		write8(ei_data) # EI_DATA 1 = little endian, 2 = big endian
		write8(1) # EI_VERSION 1 = ELF version
		write8(0) # EI_OSABI, 0=system-V, 3 = linux
		write_array([0, 0, 0, 0, 0, 0, 0, 0], size: 8)  # EI_PAD

		let e_version = 1
		write16(m_header.e_type)
		write16(m_header.e_machine)
		write32(e_version)
		write_size_t(m_header.e_entry)
		write_size_t(m_header.e_phoff)
		write_size_t(m_header.e_shoff)
		write32(m_header.e_flags)
		write16(m_header.e_ehsize)
		write16(m_header.e_phentsize)
		write16(m_header.e_phnum)
		write16(m_header.e_shentsize)
		write16(m_header.e_shnum)
		write16(m_header.e_shstrndx)

		let pos = tell()
		assert(condition: pos == 64, message: "expected position to be 64")
		assert(condition: pos == m_header.e_ehsize, message: "expected position to be e_ehsize")

	pub fn write_section_header(sh?: SectionHeader):
		if m_header.e_shoff == 0:
			# When writing the first section header
			# fill in some meta data in the header:
			m_header.e_shoff = tell()
			m_header.e_shnum = 0
		write32(sh.sh_name)
		write32(sh.sh_type)
		write_size_t(sh.sh_flags)
		write_size_t(sh.sh_addr)
		write_size_t(sh.sh_offset)
		write_size_t(sh.sh_size)
		write32(sh.sh_link)
		write32(sh.sh_info)
		write_size_t(sh.sh_addralign)
		write_size_t(sh.sh_entsize)
		m_header.e_shnum += 1
		if m_header.e_shentsize == 0:
			# Might very well be the first section header we write.
			if is_32bit:
				m_header.e_shentsize = 0x28
			else:
				m_header.e_shentsize = 0x40
			let n_written = tell() - m_header.e_shoff
			assert(condition: m_header.e_shentsize == n_written, message: "Inconsistent e_shentsize")

	fn write_program_header(ph?: ProgramHeader):
		if m_header.e_phoff == 0:
			# When writing the first section header
			# fill in some meta data in the header:
			m_header.e_phoff = tell()
			m_header.e_phnum = 0
		write32(ph.p_type)
		if not is_32bit:
			write32(ph.p_flags)
		write_size_t(ph.p_offset)
		write_size_t(ph.p_vaddr)
		write_size_t(ph.p_paddr)
		write_size_t(ph.p_filesz)
		write_size_t(ph.p_memsz)
		if is_32bit:
			write32(ph.p_flags)
		write_size_t(ph.p_align)
		m_header.e_phnum += 1
		if m_header.e_phentsize == 0:
			# Might very well be the first section header we write.
			if is_32bit:
				m_header.e_phentsize = 0x20
			else:
				m_header.e_phentsize = 0x38
			let n_written = tell() - m_header.e_phoff
			assert(condition: m_header.e_phentsize == n_written, message: "Inconsistent e_phentsize")

	pub fn seek(pos: int):
		std.file_seek(handle, pos)

	pub fn tell() -> int:
		std.file_tell(handle)

	pub fn write_bytes(data?: Bytes):
		let x = std.file_write_n_bytes(handle, buffer: data.as_array(), bufsize: data.len())
		assert(condition: x == data.len(), message: "file_write_n_bytes failed")

	fn write_array(value?: [int], size: int):
		let out = ByteArray()
		var index = 0
		while index < size:
			out.append(value[index])
			index += 1
		write_bytes(out.to_bytes())

	fn write8(value?: int):
		write_array([value], size: 1)

	fn write32(value?: int):
		let out = ByteArray()
		if is_big_endian:
			out.pack_u32_be(value)
		else:
			out.pack_u32_le(value)
		write_bytes(out.to_bytes())

	fn write16(value?: int):
		let out = ByteArray()
		if is_big_endian:
			out.pack_u16_be(value)
		else:
			out.pack_u16_le(value)
		write_bytes(out.to_bytes())

	fn write64(value?: int):
		let out = ByteArray()
		if is_big_endian:
			out.pack_u64_be(value)
		else:
			out.pack_u64_le(value)
		write_bytes(out.to_bytes())

	fn write_size_t(value?: int):
		if is_32bit:
			write32(value)
		else:
			write64(value)

class StringTable:
	var m_data: ByteArray = ByteArray()

	pub fn add_name(name?: str) -> int:
		let offset = m_data.len()
		m_data.extend(bytes_from_ascii(text: name))
		m_data.append(0)
		offset

	pub fn get_data() -> Bytes:
		m_data.to_bytes()
