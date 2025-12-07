"""
DWARF debug info.

See also: www.dwarfstd.org

"""

from logging import log_info
from bytes import ByteArray
from elf_file import StringTable
from listtype import List
from outstream import BinaryOutput, DataItem
from location import get_begin, offset_to_position
from dbginfo import DbgInfo

let DW_AT_sibling: int = 0x01
let DW_AT_location: int = 0x02
let DW_AT_name: int = 0x03
let DW_AT_low_pc: int = 0x11
let DW_AT_high_pc: int = 0x12
let DW_AT_decl_column: int = 0x39
let DW_AT_decl_file: int = 0x3A
let DW_AT_decl_line: int = 0x3B

let DW_FORM_addr: int = 0x01
let DW_FORM_block2: int = 0x03
let DW_FORM_data2: int = 0x05
let DW_FORM_data4: int = 0x06
let DW_FORM_data8: int = 0x07
let DW_FORM_udata: int = 0x0f
let DW_FORM_strp: int = 0x0E
let DW_FORM_sec_offset: int = 0x17

let DW_ATE_float: int = 0x4
let DW_ATE_signed: int = 0x5

let DW_TAG_compile_unit: int = 0x11
let DW_TAG_subprogram: int = 0x2e

let DW_CHILDREN_no: int = 0x0
let DW_CHILDREN_yes: int = 0x1

pub fn gen_debug_info(info: DbgInfo, out: BinaryOutput, emit_data: fn(DataItem, BinaryOutput)):
	""" Generate DWARF debug info into binary output. """
	log_info("Creating debug info")

	let writer = DwarfWriter(m_out: out)

	# Define abbrevs:
	let abbrevs: List[Abbrev] = List()
	let attrs1: List[AttrSpec] = List()
	let abbrev1 = Abbrev(id: 1, tag: DW_TAG_compile_unit, children: true, attrs: attrs1)
	abbrevs.append(abbrev1)

	let attrs2: List[AttrSpec] = List()
	attrs2.append(AttrSpec(name: DW_AT_name, form: DW_FORM_strp))
	attrs2.append(AttrSpec(name: DW_AT_decl_line, form: DW_FORM_udata))
	attrs2.append(AttrSpec(name: DW_AT_decl_column, form: DW_FORM_udata))
	attrs2.append(AttrSpec(name: DW_AT_low_pc, form: DW_FORM_addr))
	attrs2.append(AttrSpec(name: DW_AT_high_pc, form: DW_FORM_addr))
	let abbrev2 = Abbrev(id: 2, tag: DW_TAG_subprogram, children: false, attrs: attrs2)
	abbrevs.append(abbrev2)

	# Define sub programs
	let sub_programs: List[SubProgram] = List()
	for dbg_function in info.functions:
		let position = offset_to_position(offset: get_begin(dbg_function.location), code: dbg_function.source.code)
		log_info("Start / end = {dbg_function.start_label} end={dbg_function.end_label}")
		let sub_program = SubProgram:
			name: dbg_function.name
			line: position.row
			column: position.column
			begin: dbg_function.start_label
			end: dbg_function.end_label
		sub_programs.append(sub_program)

	writer.write_abbrevs(abbrevs)
	writer.write_debug_info(sub_programs, emit_data)
	writer.write_string_table()

class DwarfWriter:
	var m_out: BinaryOutput
	var string_table: StringTable = StringTable()

	pub fn write_debug_info(sub_programs: List[SubProgram], emit_data: fn(DataItem, BinaryOutput)):
		m_out.select_section(name: ".debug_info")

		# Compilation unit header:
		write_u32(0)  # length, we fix this later
		write_u16(4)  # DWARF V4
		write_u32(0)  # offset in abbrev section
		write_byte(8)  # address size
		uleb128(1)  # compile_unit DIE
		# TODO: global variables
		for sub_program in sub_programs:
			uleb128(2)  # subprogram DIE
			write_u32(string_table.add_name(sub_program.name))
			uleb128(sub_program.line)
			uleb128(sub_program.column)
			emit_data(DataItem.AbsPointer64(sub_program.begin), m_out)
			emit_data(DataItem.AbsPointer64(sub_program.end), m_out)
			# TODO: local variables
		write_byte(0) # End children

		let tmp2 = ByteArray()
		tmp2.pack_u32_le(m_out.get_offset() - 4)
		m_out.write_bytes_at(data: tmp2.to_bytes(), offset: 0)

	pub fn write_abbrevs(abbrevs: List[Abbrev]):
		""" Write abbreviations to .debug_abbrev section """
		m_out.select_section(name: ".debug_abbrev")
		for abbrev in abbrevs:
			write_abbrev(abbrev)
		write_byte(0)

	fn write_abbrev(abbrev: Abbrev):
		uleb128(abbrev.id)
		uleb128(abbrev.tag)
		write_byte(DW_CHILDREN_yes if abbrev.children else DW_CHILDREN_no)
		for attr_spec in abbrev.attrs:
			uleb128(attr_spec.name)
			uleb128(attr_spec.form)
		# attributes terminator:
		uleb128(0)
		uleb128(0)

	pub fn write_string_table():
		m_out.select_section(name: ".debug_str")
		m_out.write_bytes(data: string_table.get_data())

	fn write_byte(value?: int):
		m_out.write_byte(value)

	fn write_u16(value?: int):
		let tmp = ByteArray()
		tmp.pack_u16_le(value)
		m_out.write_bytes(data: tmp.to_bytes())

	fn write_u32(value?: int):
		let tmp = ByteArray()
		tmp.pack_u32_le(value)
		m_out.write_bytes(data: tmp.to_bytes())

	fn uleb128(value?: int):
		""" Encode as unsigend LEB128 in output """
		loop:
			var b = value & 0x7F
			value = value >> 7
			if value != 0:
				b = b | 0x80
			write_byte(b)
			if value == 0:
				break

struct SubProgram:
	name: str
	line: int
	column: int
	begin: str
	end: str

struct Abbrev:
	id: int
	tag: int
	children: bool
	attrs: List[AttrSpec]

struct AttrSpec:
	name: int
	form: int
