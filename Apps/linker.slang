module main

import std
from base import math
from base.listtype import List
from base.fs import Path, new_path
from base.hashmap import HashMap, new_hashmap_str
from base.logging import log_info, set_log_level
from base.utils import assert, panic
from compiler import elf

pub fn main() -> int:
	let options = parse_options()
	if options.show_help:
		print_usage()
		return 0

	if options.filenames.is_empty():
		std.print("No input")
		return 1

	set_log_level(level: options.verbosity)

	let inputs: List[InputObject] = List()
	for filename in options.filenames:
		try:
			inputs.append(load_input(filename))
		except (err: elf.Error):
			std.print("Invalid ELF file {filename} could not be opened: {err.message}")
			return 2

	let linker = Linker:
		inputs
		outputs: List()
	layout(linker)
	write_output(linker, filename: options.output)
	0

struct Linker:
	inputs: List[InputObject]
	outputs: List[OutputSection]

struct InputObject:
	reader: elf.ElfReader
	header: elf.ElfHeader
	sections: List[InputSection]

struct InputSection:
	reader: elf.ElfReader
	header: elf.SectionHeader
	name: str
	address: int
	offset: int

struct OutputSection:
	name: str
	offset: int
	sh_addralign: int
	sh_type: int
	sh_flags: int
	input_sections: List[InputSection]

struct Segment:
	sections: List[OutputSection]
	offset: int

struct Symbol:
	name: str
	value: int

fn load_input(filename: Path) -> InputObject except elf.Error:
	"""Load a single ELF file"""
	log_info("Reading {filename}")
	let reader = elf.read_elf(filename)
	let header = reader.read_header()
	let section_headers = reader.read_section_headers(header)
	let sh_strtab = reader.read_strtab(header: section_headers[header.e_shstrndx])
	let input_object = InputObject:
		reader
		header
		sections: List()
	var index = 0
	for section_header in section_headers:
		let name = sh_strtab.get_name(section_header.sh_name)
		let input_section = InputSection:
			reader
			header: section_header
			name
			address: 0
			offset: 0
		input_object.sections.append(input_section)
		index += 1
	input_object

fn layout(linker: Linker):
	# Layout input sections into outputs
	let sections_by_name: HashMap[str,OutputSection] = new_hashmap_str()
	var address = 0
	for input in linker.inputs:
		for input_section in input.sections:
			if input_section.header.sh_flags & elf.SHF_ALLOC != 0:
				# Now we are interested
				log_info("Using input {input_section.name}")
				if not sections_by_name.contains(key: input_section.name):
					log_info("Creating output section {input_section.name}")
					let out = OutputSection:
						name: input_section.name
						offset: 0
						sh_type: input_section.header.sh_type
						sh_flags: input_section.header.sh_flags
						sh_addralign: input_section.header.sh_addralign
						input_sections: List()
					sections_by_name.insert(key: input_section.name, value: out)
					linker.outputs.append(out)

				let out = sections_by_name.get(key: input_section.name)

				# Place input section into output section
				assert(condition: out.sh_type == input_section.header.sh_type, message: "Type must match")
				assert(condition: out.sh_flags == input_section.header.sh_flags, message: "Flags must match")
				out.offset = math.round_up_to_multiple(value: out.offset, multiple: input_section.header.sh_addralign)
				input_section.address = address
				input_section.offset = out.offset
				out.sh_addralign = math.max(out.sh_addralign, input_section.header.sh_addralign)
				out.input_sections.append(input_section)

				out.offset += input_section.header.sh_size

	# Now group output sections in segments?
	let segment = Segment:
		sections: List()
		offset: 0

	for section in linker.outputs:
		segment.sections.append(section)

	let symbol_table: HashMap[str,int] = new_hashmap_str()

fn write_output(linker: Linker, filename: Path):
	log_info("Creating {filename}")
	let handle = filename.open(mode: "wb")
	let writer = elf.ElfWriter(handle)
	writer.set_bitsize(bits: 64)

	# Skip over header, will be patched later.
	writer.seek(pos: writer.m_header.e_ehsize)

	# Jump over program headers:
	# TODO

	# NULL section
	let sh_null = writer.new_section(name: "")

	# Copy section data into output file:
	for output in linker.outputs:
		let section_header = writer.new_section(name: output.name)
		section_header.sh_offset = writer.tell()
		section_header.sh_type = output.sh_type
		section_header.sh_flags = output.sh_flags
		section_header.sh_size = output.offset
		section_header.sh_addralign = output.sh_addralign
		for input_section in output.input_sections:
			let data = input_section.reader.read_section(header: input_section.header)
			# Apply relocations?
			writer.write_bytes(data)

	# Write section headers and file header
	elf.write_section_headers(writer)
	writer.write_header()
	std.file_close(handle)

struct Options:
	filenames: List[Path]
	output: Path
	verbosity: int
	relocatable: bool
	show_help: bool

fn parse_options() -> Options:
	let options = Options:
		filenames: List()
		output: new_path(filename: "a.out")
		verbosity: 0
		relocatable: false
		show_help: false

	var i = 0
	let n = std.get_n_args()
	while i < n:
		let argument = std.get_arg(arg: i)
		i += 1
		if argument == "-h" or argument == "--help":
			options.show_help = true
		elif argument == "-v" or argument == "--verbose":
			options.verbosity += 1
		elif argument == "-r" or argument == "--relocatable":
			options.relocatable = true
		elif argument == "-o" or argument == "--output":
			if i < n:
				options.output = new_path(filename: std.get_arg(arg: i))
				i += 1
			else:
				panic("Expect argument to {argument}")
		else:
			options.filenames.append(new_path(filename: argument))
	options

fn print_usage():
	std.print("Usage:")
	std.print(" $ linker <options> elf-files")
	std.print("   -o --output       : output filename")
	std.print("   -r --relocatable  : generate relocatable output")
	std.print("   -v --verbose      : increate verbosity")
	std.print("   -h --help         : show help")
