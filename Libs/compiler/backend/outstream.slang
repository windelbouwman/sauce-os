""" Logic for binary object code.

Use the Outstream to contrapt an Object struct, with code and data section.
"""

from optiontype import Option
from utils import panic
from logging import log_debug
from hashmap import HashMap, new_hashmap_str
from vectype import Vector, new_vector
from deque import Queue, new_queue
from bytes import ByteArray, Bytes

pub struct Object:
	""" Code object """
	sections: Vector[Section]
	symbols: Vector[Symbol]

pub struct Section:
	name: str
	data: ByteArray
	relocations: Vector[Relocation]
	alignment: int
	executable: bool
	writable: bool

pub struct Relocation:
	symbol: str
	offset: int
	typ: int
	addend: int

pub struct Symbol:
	name: str
	kind: SymbolKind

pub enum SymbolKind:
	Extern
	Intern(section: Section, offset: int, global: bool)

fn make_section(name: str) -> Section:
	Section:
		name
		data: ByteArray()
		relocations: new_vector()
		alignment: 1
		executable: false
		writable: false

struct Fixup:
	symbol: str
	section: Section
	offset: int
	typ: int
	addend: int

pub class BinaryOutput:
	var sections: HashMap[str, Section] = new_hashmap_str()
	var current_section: Option[str] = Option.None()
	var symbols: HashMap[str, Symbol] = new_hashmap_str()
	var fixups: Queue[Fixup] = new_queue()
	var tmp_labels: Queue[str] = new_queue()

	pub fn select_section(name: str):
		if not sections.contains(key: name):
			let new_section = make_section(name)
			sections.insert(key: name, value: new_section)
		current_section = Option.Some(name)

	fn get_current_section() -> Section:
		case current_section:
			Some(name):
				sections.get(key: name)
			None:
				panic("No output section selected")

	pub fn import_symbol(name?: str):
		""" Define symbol which lives externally """
		define_symbol(name, kind: SymbolKind.Extern())

	pub fn export_symbol(name?: str):
		""" Define symbol, which can be used elsewhere """
		define(name, global: true)

	pub fn local_symbol(name?: str):
		define(name, global: false)

	pub fn define_label(name?: str):
		define(name, global: false)
		tmp_labels.push(name)

	pub fn set_writable():
		let section = get_current_section()
		section.writable = true

	pub fn set_executable():
		let section = get_current_section()
		section.executable = true

	fn define(name: str, global: bool):
		""" Define a symbol at the current cursor """
		let section = get_current_section()
		let offset = section.data.len()
		define_symbol(name, kind: SymbolKind.Intern(section, offset, global))

	fn define_symbol(name: str, kind: SymbolKind):
		if symbols.contains(key: name):
			panic("Duplicate symbol: {name}")
		else:
			let symbol = Symbol(name, kind)
			symbols.insert(key: name, value: symbol)

	pub fn add_fixup(symbol: str, typ: int, addend: int):
		""" Add relocation information at the current position. """
		let section = get_current_section()
		let offset = section.data.len()
		fixups.push(Fixup(symbol, section, offset, typ, addend))

	pub fn do_fixups(fixer: fn(ByteArray, int, int, int, int), is_pic_reloc: fn(int) -> bool):
		# Apply relocation action now,
		# or emit full blown relocation record
		# for the linker to fix later.
		while not fixups.is_empty():
			let fixup = fixups.pop()
			if symbols.contains(key: fixup.symbol):
				let symbol = symbols.get(key: fixup.symbol)
				case symbol.kind:
					Intern(section, offset, global):
						if (not global) and (section.name == fixup.section.name) and is_pic_reloc(fixup.typ):
							# apply reloc locally!
							log_debug("Apply reloc now {fixup.symbol}")
							fixer(data: fixup.section.data, fixup.offset, fixup.typ, fixup.addend, offset)
							continue
						else:
							log_debug("Not section local: {fixup.symbol}")
					Extern:
						log_debug("External symbol: {fixup.symbol}")
			else:
				log_debug("Not found: {fixup.symbol}")

			# Emit relocation into object file
			log_debug("Emit reloc for {fixup.symbol}")
			let relocation = Relocation(symbol: fixup.symbol, offset: fixup.offset, typ: fixup.typ, addend: fixup.addend)
			fixup.section.relocations.append(relocation)

		while not tmp_labels.is_empty():
			let name = tmp_labels.pop()
			symbols.remove(key: name)

	pub fn write_byte(value?: int):
		let section = get_current_section()
		section.data.append(value)

	pub fn write_bytes(data: Bytes):
		let section = get_current_section()
		section.data.extend(data)

	pub fn get_section(name: str) -> Section:
		sections.get(key: name)

	pub fn get_object() -> Object:
		let sections_vector: Vector[Section] = new_vector()
		for name in sections:
			sections_vector.append(sections.get(key: name))
		let symbols_vector: Vector[Symbol] = new_vector()
		for name in symbols:
			symbols_vector.append(symbols.get(key: name))
		Object(sections: sections_vector, symbols: symbols_vector)
