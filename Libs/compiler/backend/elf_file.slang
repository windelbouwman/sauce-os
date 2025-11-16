"""
ELF file format
"""

import std
from listtype import List
from bytes import Bytes, ByteArray, new_bytes, bytes_from_ascii
from utils import assert, panic
from logging import log_error, log_info
from hashmap import HashMap, new_hashmap_str
from outstream import Object, Section

let SHN_UNDEF: int = 0

let SHT_NULL: int = 0
let SHT_PROGBITS: int = 1
let SHT_SYMTAB: int = 2
let SHT_STRTAB: int = 3
let SHT_RELA: int = 4

let SHF_WRITE: int = 0x1
let SHF_ALLOC: int = 0x2
let SHF_EXECINSTR: int = 0x4
let SHF_INFO_LINK: int = 0x40

let STB_LOCAL: int = 0
let STB_GLOBAL: int = 1
let STB_WEAK: int = 2

let STT_NOTYPE: int = 0
let STT_OBJECT: int = 1
let STT_FUNC: int = 2
let STT_SECTION: int = 3
let STT_FILE: int = 4
let STT_COMMON: int = 5
let STT_TLS: int = 6

pub fn write_elf(filename: str, object: Object):
	""" Write ELF file."""
	log_info("Writing elf file: {filename}")
	let handle = std.file_open(filename, mode: "wb")
	let writer = ElfWriter(handle)

	# Skip over header, will be patched later.
	writer.seek(pos: writer.m_header.e_ehsize)

	let sh_null = writer.new_section(name: "")
	# TODO: write eventual program headers here

	let symbol_map: HashMap[str, int] = new_hashmap_str()  # Map name -> symbol table index
	fill_symbols(writer, object, symbol_map)
	for section in object.sections:
		write_section(writer, section, symbol_map)
	write_symbol_table(writer, object)
	write_section_headers(writer)
	writer.seek(pos: 0)
	writer.write_header()
	std.file_close(handle)

fn fill_symbols(writer: ElfWriter, object: Object, symbol_map: HashMap[str, int]):
	""" Fill symbol index map """
	# TODO: perform 2 loops, to fill local symbols first, then global symbols?

	# Special NULL entry:
	var index = 1

	for symbol in object.symbols:
		if symbol_map.contains(key: symbol.name):
			panic("Duplicate symbol: {symbol.name}")
		else:
			symbol_map.insert(key: symbol.name, value: index)
		index += 1

fn write_section(writer: ElfWriter, section: Section, symbol_map: HashMap[str, int]):
	"""Write a single section"""
	log_info("Writing section {section.name} of {section.data.len()} bytes")
	let sh_text = writer.new_section(name: section.name)
	writer.write_section_data(sh: sh_text, data: section.data.to_bytes())
	sh_text.sh_type = SHT_PROGBITS
	sh_text.sh_flags = SHF_ALLOC | SHF_EXECINSTR
	sh_text.sh_addralign = section.alignment

	# Add relocation info for this section
	if not section.relocations.is_empty():
		let sh_rela = writer.new_section(name: ".rela.{section.name}")
		sh_rela.sh_type = SHT_RELA
		sh_rela.sh_flags = SHF_INFO_LINK
		sh_rela.sh_link = 999 # To be filled later
		sh_rela.sh_info = writer.get_section_index(name: section.name)
		sh_rela.sh_entsize = 24  # In case of 64 bit
		sh_rela.sh_offset = writer.tell()
		for reloc in section.relocations:
			if not symbol_map.contains(key: reloc.symbol):
				panic("Undefined symbol: {reloc.symbol}")
			let sym = symbol_map.get(key: reloc.symbol)
			let rte = RelaTableEntry:
				r_offset: reloc.offset
				r_info: (sym << 32) | reloc.typ
				r_addend: reloc.addend
			writer.write_rela_entry(rte)
		sh_rela.sh_size = writer.tell() - sh_rela.sh_offset

fn write_symbol_table(writer: ElfWriter, object: Object):
	let st_null = writer.new_symbol(name: "UNDEF")

	for symbol in object.symbols:
		let ste = writer.new_symbol(name: symbol.name)
		case symbol.kind:
			Intern(section, offset, global):
				ste.st_value = offset
				let bind = STB_GLOBAL if global else STB_LOCAL
				let ty = STT_FUNC if global else STT_NOTYPE
				ste.st_info = (bind << 4) | ty
				ste.st_shndx = writer.get_section_index(name: section.name)
			Extern:
				let bind = STB_GLOBAL
				let ty = STT_FUNC
				ste.st_info = (bind << 4) | ty

	# Symbol table:
	let sh_symtab = writer.new_section(name: ".symtab")
	sh_symtab.sh_type = SHT_SYMTAB
	sh_symtab.sh_offset = writer.tell()
	sh_symtab.sh_addralign = 1
	sh_symtab.sh_link = writer.section_headers.len()  # str tab follows directly
	sh_symtab.sh_info = 1  # Index of first global symbol
	sh_symtab.sh_entsize = 24
	for ste in writer.symbol_table:
		writer.write_symtab_entry(ste)
	sh_symtab.sh_size = writer.tell() - sh_symtab.sh_offset
	let sh_symtab_ndx = writer.section_headers.len() - 1
	# Patch RELA sh_link to point to this symbol table:
	for sh in writer.section_headers:
		if sh.sh_type == SHT_RELA:
			sh.sh_link = sh_symtab_ndx

	let sh_strtab = writer.new_section(name: ".strtab")
	writer.write_section_data(sh: sh_strtab, data: writer.strtab.get_data())
	sh_strtab.sh_type = SHT_STRTAB
	sh_strtab.sh_addralign = 1

fn write_section_headers(writer: ElfWriter):
	# section header string table
	let sh_shstrtab = writer.new_section(name: ".shstrtab")
	sh_shstrtab.sh_type = SHT_STRTAB
	sh_shstrtab.sh_addralign = 1
	writer.write_section_data(sh: sh_shstrtab, data: writer.sh_string_table.get_data())

	# Write section headers now:
	for sh in writer.section_headers:
		writer.write_section_header(sh)
	writer.m_header.e_shstrndx = writer.m_header.e_shnum - 1

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
		e_type: 1  # 0=None, 1=REL, 2=exec, 3=dynamic
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

struct SymbolTableEntry:
	st_name: int
	st_value: int
	st_size: int
	st_info: int
	st_other: int
	st_shndx: int

struct RelaTableEntry:
	r_offset: int
	r_info: int
	r_addend: int

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
	pub var sh_string_table: StringTable = StringTable()
	pub var section_headers: List[SectionHeader] = List()
	var section_ids: HashMap[str, int] = new_hashmap_str()
	pub var symbol_table: List[SymbolTableEntry] = List()
	pub var strtab: StringTable = StringTable()

	pub fn new_symbol(name: str) -> SymbolTableEntry:
		let entry = SymbolTableEntry:
			st_name: strtab.add_name(name)
			st_value: 0
			st_size: 0
			st_info: 0
			st_other: 0
			st_shndx: 0
		symbol_table.append(entry)
		entry

	pub fn new_section(name: str) -> SectionHeader:
		let sh = new_sh()
		sh.sh_name = sh_string_table.add_name(name)
		if section_ids.contains(key: name):
			panic("Duplicate section: {name}")
		else:
			section_ids.insert(key: name, value: section_headers.len())
		section_headers.append(sh)
		sh

	pub fn get_section_index(name: str) -> int:
		section_ids.get(key: name)

	pub fn write_section_data(sh: SectionHeader, data: Bytes):
		""" Write data, recording offset and size """
		sh.sh_offset = tell()
		write_bytes(data)
		sh.sh_size = tell() - sh.sh_offset

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

	pub fn write_symtab_entry(ste?: SymbolTableEntry):
		write32(ste.st_name)
		if is_32bit:
			write32(ste.st_value)
			write32(ste.st_size)
		write8(ste.st_info)
		write8(ste.st_other)
		write16(ste.st_shndx)
		if not is_32bit:
			write64(ste.st_value)
			write64(ste.st_size)

	pub fn write_rela_entry(rte?: RelaTableEntry):
		write_size_t(rte.r_offset)
		write_size_t(rte.r_info)
		write_size_t(rte.r_addend)

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
