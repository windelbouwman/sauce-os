module main
"""Read elf utility"""

from std import read_file, print, get_n_args, get_arg
from base.listtype import List
from base.vectype import Vector
from base.logging import log_error
from base.strlib import int_to_hex_string, str_pad_left, str_pad_right
from compiler.elf_file import read_elf, ElfReader, StringTable
from compiler.elf_file import ElfHeader, SectionHeader

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

fn show_elf(options: Options, filename: str):
	let reader = read_elf(filename)
	try:
		let header = reader.read_header()
		if options.show_header:
			print_header(header)

		let section_headers = reader.read_section_headers(header)
		let sh_strtab_data = reader.read_section(header: section_headers[header.e_shstrndx])
		let sh_strtab = StringTable()
		sh_strtab.set_data(data: sh_strtab_data)

		if options.show_sections:
			print_section_headers(section_headers, sh_strtab)

		if options.show_symbols:
			for section_header in section_headers:
				if section_header.sh_type == 2:
					print_symbols(reader, symtab_section: section_header, strtab_section: section_headers[section_header.sh_link])
	except (err: str):
		log_error("Error reading ELF file: {err}")
	reader.close()

fn print_header(header: ElfHeader):
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

fn print_section_headers(section_headers: Vector[SectionHeader], sh_strtab: StringTable):
	print("Section headers:")
	print("[Nr] Name              Type             Address           Offset")
	print("     Size              EntSize          Flags  Link Info Align")
	var i = 0
	for section_header in section_headers:
		let sh_name_str = sh_strtab.get_name(section_header.sh_name)
		print("[ {i}] {str16(sh_name_str)}  {sh_type_str(section_header.sh_type)} {hex64(section_header.sh_addr)}  {hex32(section_header.sh_offset)}")
		print("     {hex64(section_header.sh_size)}  {hex64(section_header.sh_entsize)} {section_header.sh_flags}  {section_header.sh_link}  {section_header.sh_info}  {section_header.sh_addralign}")
		i += 1

fn sh_type_str(value?: int) -> str:
	str16(str(value))

fn str16(text?: str) -> str:
	str_pad_right(text, length: 16, fill: " ")

fn hex32(value?: int) -> str:
	str_pad_left(text: int_to_hex_string(value), length: 8, fill: "0")

fn hex64(value?: int) -> str:
	str_pad_left(text: int_to_hex_string(value), length: 16, fill: "0")

fn print_symbols(reader: ElfReader, symtab_section: SectionHeader, strtab_section: SectionHeader):
	let strtab_data = reader.read_section(header: strtab_section)
	let strtab = StringTable()
	strtab.set_data(data: strtab_data)

	let entries = reader.read_symbol_table(symtab_section)
	print("Symbol table contains {entries.len()} entries:")
	print("Num  Value   Size  Type  Bind Vis  Ndx   Name")
	var i = 0
	for entry in entries:
		let name = strtab.get_name(entry.st_name)
		print("{i}: {hex64(entry.st_value)}  {entry.st_size} {entry.st_shndx} {name}")
		i += 1

struct Options:
	filenames: List[str]
	show_header: bool
	show_sections: bool
	show_symbols: bool
	show_help: bool

fn parse_options() -> Options:
	let options = Options:
		filenames: List()
		show_header: true
		show_sections: false
		show_symbols: false
		show_help: false

	var i = 0
	let n = get_n_args()
	while i < n:
		let argument = get_arg(arg: i)
		if argument == "-a" or argument == "--all":
			options.show_header = true
			options.show_sections = true
			options.show_symbols = true
		elif argument == "-h":
			options.show_header = true
		elif argument == "-S":
			options.show_sections = true
		elif argument == "-s" or argument == "--syms":
			options.show_symbols = true
		elif argument == "-H" or argument == "--help":
			options.show_help = true
		else:
			options.filenames.append(argument)
		i += 1
	options

fn print_usage():
	print("Usage:")
	print("$ readelf <options> elf-file")
	print("")
	print("   -a --all  : all, -h -S")
	print("   -h        : print header")
	print("   -S        : display section headers")
	print("   -s        : display symbols")
	print("   -H --help : show help")
