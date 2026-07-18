module main
"""Read elf utility"""

from std import print, get_n_args, get_arg
from base.listtype import List
from base.vectype import Vector
from base.logging import log_error
from base.fs import Path, new_path
from base.strlib import int_to_hex_string, str_pad_left, str_pad_right
from compiler import elf

pub fn main() -> int:
	let options = parse_options()
	if options.show_help:
		print_usage()
		return 0

	if options.filenames.is_empty():
		print_usage()
		return 1

	for filename in options.filenames:
		show_elf(options, filename)
	0

fn show_elf(options: Options, filename: Path):
	let reader = elf.read_elf(filename)
	try:
		let header = reader.read_header()
		if options.show_header:
			print_header(header)

		let section_headers = reader.read_section_headers(header)
		let sh_strtab = reader.read_strtab(header: section_headers[header.e_shstrndx])

		if options.show_programs:
			print_program_headers(program_headers: reader.read_program_headers(header))

		if options.show_sections:
			print_section_headers(section_headers, sh_strtab)

		if options.show_symbols:
			for section_header in section_headers:
				if section_header.sh_type == elf.SHT_SYMTAB:
					print_symbols(reader, symtab_section: section_header, strtab_section: section_headers[section_header.sh_link])

		if options.show_relocs:
			for section_header in section_headers:
				if section_header.sh_type == elf.SHT_RELA:
					let symtab_section = section_headers[section_header.sh_link]
					let strtab_section = section_headers[symtab_section.sh_link]
					print_relocs(reader, reloc_section: section_header, symtab_section, strtab_section)

	except (err: elf.Error):
		log_error("Error reading ELF file: {err.message}")
	reader.close()

fn print_header(header: elf.ElfHeader):
	print("Type:                              {header.e_type}")
	print("Machine:                           {header.e_machine}")
	print("Version:                           {header.e_version}")
	print("Entry point address:               {header.e_entry}")
	print("Start of program headers:          {header.e_phoff} (bytes into file)")
	print("Start of section headers:          {header.e_shoff} (bytes into file)")
	print("Flags:                             {header.e_flags}")
	print("Size of this header:               {header.e_ehsize} (bytes)")
	print("Size of program headers:           {header.e_phentsize} (bytes)")
	print("Number of program headers:         {header.e_phnum}")
	print("Size of section headers:           {header.e_shentsize} (bytes)")
	print("Number of section headers:         {header.e_shnum}")
	print("Section header string table index: {header.e_shstrndx}")

fn print_program_headers(program_headers: Vector[elf.ProgramHeader]):
	if program_headers.is_empty():
		print("No program headers")
		return
	print("Program headers:")
	print("Type             Offset           VirtAddr         PhysAddr")
	print("                 Filesize         MemSiz           Flags  Align")
	for program_header in program_headers:
		let type_str = str_left(elf.program_header_type_to_string(program_header.p_type), width: 16)
		let flags_str = str_left(elf.program_header_flags_to_string(program_header.p_flags), width: 5)
		let offset_str = hex64(program_header.p_offset)
		let vaddr_str = hex64(program_header.p_vaddr)
		let paddr_str = hex64(program_header.p_paddr)
		let filesz_str = hex64(program_header.p_filesz)
		let memsz_str = hex64(program_header.p_memsz)
		let align_str = program_header.p_align
		print("{type_str} {offset_str} {vaddr_str} {paddr_str}")
		print("                 {filesz_str} {memsz_str} {flags_str}  {align_str}")

fn print_section_headers(section_headers: Vector[elf.SectionHeader], sh_strtab: elf.StringTable):
	if section_headers.is_empty():
		print("No section headers")
		return
	print("Section headers:")
	print("[Nr] Name              Type             Address           Offset")
	print("     Size              EntSize          Flags  Link  Info  Align")
	var i = 0
	for section_header in section_headers:
		let nr_str = str_right(str(i), width: 2)
		let name_str = str16(sh_strtab.get_name(section_header.sh_name))
		let type_str = sh_type_str(section_header.sh_type)
		let addr_str = hex64(section_header.sh_addr)
		let offset_str = hex32(section_header.sh_offset)
		let size_str = hex64(section_header.sh_size)
		let entsize_str = hex64(section_header.sh_entsize)
		let flags_str = str_left(elf.flags_to_string(section_header.sh_flags), width: 5)
		let link_str = str_left(str(section_header.sh_link), width: 4)
		let info_str = str_left(str(section_header.sh_info), width: 4)
		let align_str = str(section_header.sh_addralign)
		print("[{nr_str}] {name_str}  {type_str} {addr_str}  {offset_str}")
		print("     {size_str}  {entsize_str} {flags_str}  {link_str}  {info_str}  {align_str}")
		i += 1

fn sh_type_str(value?: int) -> str:
	str16(elf.section_header_type_to_string(value))

fn str16(text?: str) -> str:
	str_pad_right(text, length: 16, fill: " ")

fn str_right(text?: str, width: int) -> str:
	str_pad_left(text, length: width, fill: " ")

fn str_left(text?: str, width: int) -> str:
	str_pad_right(text, length: width, fill: " ")

fn hex(value?: int, width: int) -> str:
	str_pad_left(text: int_to_hex_string(value), length: width, fill: "0")

fn hex32(value?: int) -> str:
	hex(value, width: 8)

fn hex64(value?: int) -> str:
	hex(value, width: 16)

fn print_symbols(reader: elf.ElfReader, symtab_section: elf.SectionHeader, strtab_section: elf.SectionHeader):
	let strtab = reader.read_strtab(header: strtab_section)

	let entries = reader.read_symbol_table(symtab_section)
	print("Symbol table contains {entries.len()} entries:")
	print("Num  Value   Size  Type  Bind Vis  Ndx   Name")
	var i = 0
	for entry in entries:
		let name = strtab.get_name(entry.st_name)
		let value_str = hex64(entry.st_value)
		print("{i}: {value_str}  {entry.st_size} {entry.st_shndx} {name}")
		i += 1

fn print_relocs(reader: elf.ElfReader, reloc_section: elf.SectionHeader, symtab_section: elf.SectionHeader, strtab_section: elf.SectionHeader):
	let strtab = reader.read_strtab(header: strtab_section)
	let symbol_table = reader.read_symbol_table(symtab_section)
	let relas = reader.read_relas(reloc_section)
	print("Relocations with {relas.len()} entries:")
	print("Offset   Info   Type  Value  Name + addend")
	for entry in relas:
		let offset_str = hex64(entry.r_offset)
		let info_str = hex64(entry.r_info)
		# TODO: support 32 bit here.
		let typ = entry.r_info & 0xffffffff
		let symbol = (entry.r_info >> 32) & 0xffffffff
		let symbol_table_entry = symbol_table[symbol]
		let type_str = str(typ)
		let addend_str = entry.r_addend
		let name = strtab.get_name(symbol_table_entry.st_name)
		print("{offset_str}  {info_str} {type_str} {name} + {addend_str}")

struct Options:
	filenames: List[Path]
	show_header: bool
	show_sections: bool
	show_programs: bool
	show_symbols: bool
	show_relocs: bool
	show_help: bool

fn parse_options() -> Options:
	let options = Options:
		filenames: List()
		show_header: true
		show_sections: false
		show_programs: false
		show_symbols: false
		show_relocs: false
		show_help: false

	var i = 0
	let n = get_n_args()
	while i < n:
		let argument = get_arg(arg: i)
		if argument == "-a" or argument == "--all":
			options.show_header = true
			options.show_programs = true
			options.show_sections = true
			options.show_symbols = true
			options.show_relocs = true
		elif argument == "-h" or argument == "--file-header":
			options.show_header = true
		elif argument == "-l" or argument == "--program-headers":
			options.show_programs = true
		elif argument == "-S" or argument == "--section-headers":
			options.show_sections = true
		elif argument == "-s" or argument == "--syms":
			options.show_symbols = true
		elif argument == "-r" or argument == "--relocs":
			options.show_relocs = true
		elif argument == "-H" or argument == "--help":
			options.show_help = true
		else:
			options.filenames.append(new_path(filename: argument))
		i += 1
	options

fn print_usage():
	print("Usage:")
	print("$ readelf <options> elf-file")
	print("")
	print("   -a --all             : all, -h -l -S -s -r")
	print("   -h --file-header     : print header")
	print("   -l --program-headers : display program headers")
	print("   -S --section-headers : display section headers")
	print("   -s --syms            : display symbols")
	print("   -r --relocs          : display symbols")
	print("   -H --help            : show help")
