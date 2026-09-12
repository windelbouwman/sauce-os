module main

from std import print
import std
from base.fs import Path, new_path
from base.optiontype import Option, option_unwrap
from base.listtype import List
from base.bytes import Bytes, ByteReader, bytes_to_ascii
from base import leb128
from base.utils import panic, unimplemented
from compiler import webassembly
from compiler.text_gen import TextGenerator

pub fn main() -> int:
	let options = parse_options()
	if options.show_help:
		show_usage()
		return 0
	if options.filenames.len() != 1:
		show_usage()
		return 1
	let filename = options.filenames.get(index: 0)
	let wasm_module = read_wasm(filename)
	let out = TextGenerator()
	out.begin(output_filename: options.output_file)
	webassembly.to_wat(wasm_module, out)
	out.end()
	0

fn show_usage():
	print("Wasm toolkit")
	print("Usage:")
	print("   $ wabt.exe [options] file")
	print("Options:")
	print("   -h --help    : show help")
	print("   -o --output  : output file")

struct Options:
	filenames: List[Path]
	output_file: Option[Path]
	show_help: bool

fn parse_options() -> Options:
	let options = Options:
		filenames: List()
		output_file: Option.None()
		show_help: false
	var i = 0
	let n = std.get_n_args()
	while i < n:
		let argument = std.get_arg(arg: i)
		i += 1
		if argument == "-h" or argument == "--help":
			options.show_help = true
		elif argument == "-o" or argument == "--output":
			if i < n:
				options.output_file = Option.Some(new_path(filename: std.get_arg(arg: i)))
				i += 1
			else:
				print("Expect argument to {argument}")
		else:
			options.filenames.append(new_path(filename: argument))
	options

fn read_wasm(filename: Path) -> webassembly.Module:
	"""Wasm binary parser"""
	print("Reading {filename}")
	let data = filename.read_bytes()
	print("Read {data.len()} bytes")
	load_wasm_from_bytes(data)

fn load_wasm_from_bytes(data: Bytes) -> webassembly.Module:
	let types: List[webassembly.CompType] = List()
	let imports: List[webassembly.Import] = List()
	let tags: List[webassembly.Tag] = List()
	let globals: List[webassembly.Global] = List()
	let functions: List[webassembly.Function] = List()
	let exports: List[webassembly.Export] = List()
	let datas: List[webassembly.Data] = List()

	let r_top = Reader(m_reader: ByteReader(m_bytes: data))
	let header = r_top.read_bytes(size: 8)
	while not r_top.at_end():
		let section = read_section(reader: r_top)
		let r2 = Reader(m_reader: ByteReader(m_bytes: section.data))
		if section.id == 1:
			parse_types(reader: r2, types)
		elif section.id == 2:
			read_imports(reader: r2, imports)
		elif section.id == 3:
			read_func_section(reader: r2, functions)
		elif section.id == 7:
			read_exports(reader: r2, exports)
		elif section.id == 10:
			read_code(reader: r2, functions)
		elif section.id == 11:
			read_datas(reader: r2, datas)
		elif section.id == 12:
			pass  # skip data count section
		else:
			unimplemented("Section: {section.id}")

	webassembly.Module:
		types
		imports
		tags
		globals
		functions
		exports
		datas

fn parse_types(reader: Reader, types: List[webassembly.CompType]):
	var count = reader.read_u32()
	while count > 0:
		types.append(parse_type(reader))
		count -= 1

fn parse_field_type(reader: Reader) -> webassembly.FieldType:
	let ty = switch reader.peek_byte():
		0x77:
			reader.skip_byte()
			webassembly.StorageType.Packed(webassembly.PackType.i16())
		0x78:
			reader.skip_byte()
			webassembly.StorageType.Packed(webassembly.PackType.i8())
	else:
		webassembly.StorageType.Value(read_value_type(reader))

	let mutable_byte = reader.read_byte()
	let mutable = mutable_byte == 0x1
	webassembly.FieldType(mutable, ty)

fn parse_type(reader: Reader) -> webassembly.CompType:
	let t = reader.read_byte()
	switch t:
		0x5F:
			let fields: List[webassembly.FieldType] = List()
			var n_fields = reader.read_u32()
			while n_fields > 0:
				fields.append(parse_field_type(reader))
				n_fields -= 1
			webassembly.CompType.Struct(fields)
		0x5E:
			webassembly.CompType.Array(ty: parse_field_type(reader))
		0x60:
			var n_params = reader.read_u32()
			let params: List[webassembly.ValueType] = List()
			while n_params > 0:
				params.append(read_value_type(reader))
				n_params -= 1
			var n_results = reader.read_u32()
			let results: List[webassembly.ValueType] = List()
			while n_results > 0:
				results.append(read_value_type(reader))
				n_results -= 1
			webassembly.CompType.Func(params, results)
	else:
		panic("Bad type: {t}")

fn read_value_type(reader: Reader) -> webassembly.ValueType:
	let t = reader.read_byte()
	switch t:
		0x7C: webassembly.ValueType.Num(webassembly.NumType.f64())
		0x7D: webassembly.ValueType.Num(webassembly.NumType.f32())
		0x7E: webassembly.ValueType.Num(webassembly.NumType.i64())
		0x7F: webassembly.ValueType.Num(webassembly.NumType.i32())
		0x63: webassembly.ValueType.Ref(read_ref_type(reader, nullable: true))
		0x64: webassembly.ValueType.Ref(read_ref_type(reader, nullable: false))
		0x6E: webassembly.ValueType.Ref(webassembly.RefType(nullable: false, heap_type: webassembly.HeapType.Any()))
		0x6F: webassembly.ValueType.Ref(webassembly.RefType(nullable: false, heap_type: webassembly.HeapType.Extern()))
	else:
		panic("Bad value type: {t}")

fn read_heap_type(reader: Reader) -> webassembly.HeapType:
	if reader.peek_byte() >= 0x40:
		let t = reader.read_byte()
		switch t:
			0x6C: webassembly.HeapType.i31()
			0x6E: webassembly.HeapType.Any()
			0x6F: webassembly.HeapType.Extern()
			0x70: webassembly.HeapType.Func()
		else:
			panic("Bad heap type: {t}")
	else:
		let index = reader.read_s32()
		webassembly.HeapType.TypeIdx(index)

fn read_imports(reader: Reader, imports: List[webassembly.Import]):
	var count = reader.read_u32()
	while count > 0:
		count -= 1
		imports.append(read_import(reader))

fn read_import(reader: Reader) -> webassembly.Import:
	let modname = read_str(reader)
	let name = read_str(reader)
	let t = reader.read_byte()
	let kind = switch t:
		0x0:
			let index = reader.read_u32()
			webassembly.ExternType.Func(index)
		0x3:
			let ty = read_value_type(reader)
			let mutable_byte = reader.read_byte()
			let mutable = mutable_byte == 1
			webassembly.ExternType.Global(ty, mutable)
		0x4:
			let skip = reader.read_byte()
			let typeidx = reader.read_u32()
			webassembly.ExternType.Tag(typeidx)
	else:
		panic("Bad import: {t}")
	webassembly.Import(modname, name, kind)

fn read_func_section(reader: Reader, functions: List[webassembly.Function]):
	var count = reader.read_u32()
	while count > 0:
		count -= 1
		let typeidx = reader.read_u32()
		let locals: List[webassembly.ValueType] = List()
		let code: List[webassembly.Instruction] = List()
		let func = webassembly.Function(typeidx, locals, code)
		functions.append(func)

fn read_exports(reader: Reader, exports: List[webassembly.Export]):
	var count = reader.read_u32()
	while count > 0:
		count -= 1
		exports.append(read_export(reader))

fn read_export(reader: Reader) -> webassembly.Export:
	let name = read_str(reader)
	let t = reader.read_byte()
	let kind = switch t:
		0x0:
			let index = reader.read_u32()
			webassembly.ExportKind.Func(index)
		0x1:
			let index = reader.read_u32()
			webassembly.ExportKind.Table(index)
		0x2:
			let index = reader.read_u32()
			webassembly.ExportKind.Memory(index)
		0x3:
			let index = reader.read_u32()
			webassembly.ExportKind.Global(index)
		0x4:
			let index = reader.read_u32()
			webassembly.ExportKind.Tag(index)
	else:
		panic("Bad export: {t}")
	webassembly.Export(name, kind)

fn read_code(reader: Reader, functions: List[webassembly.Function]):
	var count = reader.read_u32()
	let function_iter = functions.iter()
	while count > 0:
		count -= 1
		let data = read_blob(reader)
		let r2 = Reader(m_reader: ByteReader(m_bytes: data))
		let function = option_unwrap(function_iter.next())
		read_1_code(reader: r2, function)

fn read_1_code(reader: Reader, function: webassembly.Function):
	"""Read locals + code for a single function"""
	var n_locals = reader.read_u32()
	while n_locals > 0:
		n_locals -= 1
		var n = reader.read_u32()
		let ty = read_value_type(reader)
		while n > 0:
			n -= 1
			function.locals.append(ty)
	while not reader.at_end():
		function.code.append(decode_opcode(reader))

fn read_block_type(reader: Reader) -> webassembly.BlockType:
	let params: List[webassembly.ValueType] = List()
	let results: List[webassembly.ValueType] = List()
	if reader.peek_byte() == 0x40:
		reader.skip_byte()
	else:
		results.append(read_value_type(reader))
	webassembly.BlockType(params, results)

fn decode_opcode(reader: Reader) -> webassembly.Instruction:
	let t = reader.read_byte()
	switch t:
		0x00: webassembly.Instruction.ctrl_unreachable()
		0x01: webassembly.Instruction.ctrl_nop()
		0x02: webassembly.Instruction.ctrl_block(block_type: read_block_type(reader))
		0x03: webassembly.Instruction.ctrl_loop(block_type: read_block_type(reader))
		0x04: webassembly.Instruction.ctrl_if(block_type: read_block_type(reader))
		0x05: webassembly.Instruction.ctrl_else()
		0x08: webassembly.Instruction.ctrl_throw(index: reader.read_u32())
		0x0B: webassembly.Instruction.ctrl_end()
		0x0C: webassembly.Instruction.ctrl_br(labelidx: reader.read_u32())
		0x0D: webassembly.Instruction.ctrl_br_if(labelidx: reader.read_u32())
		0x0E: webassembly.Instruction.ctrl_br_table()
		0x0F: webassembly.Instruction.ctrl_return()
		0x10: webassembly.Instruction.ctrl_call(funcidx: reader.read_u32())
		0x11: webassembly.Instruction.ctrl_call_indirect(tableidx: reader.read_u32())
		0x14: webassembly.Instruction.ctrl_call_ref(ty: reader.read_u32())
		0x1A: webassembly.Instruction.drop()

		0x1F:
			let block_type = read_block_type(reader)
			var count = reader.read_u32()
			let catches: List[webassembly.CatchItem] = List()
			while count > 0:
				count -= 1
				let a = reader.read_byte()
				switch a:
					0x0:
						let tagindex = reader.read_u32()
						let label = reader.read_u32()
						catches.append(webassembly.CatchItem.Catch(tagindex, label))
				else:
					panic("Bad catch")
			webassembly.Instruction.ctrl_try_table(block_type, catches)

		0x20: webassembly.Instruction.local_get(localidx: reader.read_u32())
		0x21: webassembly.Instruction.local_set(localidx: reader.read_u32())
		0x22: webassembly.Instruction.local_tee(localidx: reader.read_u32())
		0x23: webassembly.Instruction.global_get(globalidx: reader.read_u32())
		0x24: webassembly.Instruction.global_set(globalidx: reader.read_u32())

		0x28:
			let align = reader.read_u32()
			let offset = reader.read_u32()
			webassembly.Instruction.i32_load(align, offset)
		0x29:
			let align = reader.read_u32()
			let offset = reader.read_u32()
			webassembly.Instruction.i64_load(align, offset)
		0x2A:
			let align = reader.read_u32()
			let offset = reader.read_u32()
			webassembly.Instruction.f32_load(align, offset)
		0x2B:
			let align = reader.read_u32()
			let offset = reader.read_u32()
			webassembly.Instruction.f64_load(align, offset)

		0x36:
			let align = reader.read_u32()
			let offset = reader.read_u32()
			webassembly.Instruction.i32_store(align, offset)
		0x37:
			let align = reader.read_u32()
			let offset = reader.read_u32()
			webassembly.Instruction.i64_store(align, offset)
		0x38:
			let align = reader.read_u32()
			let offset = reader.read_u32()
			webassembly.Instruction.f32_store(align, offset)
		0x39:
			let align = reader.read_u32()
			let offset = reader.read_u32()
			webassembly.Instruction.f64_store(align, offset)

		0x41: webassembly.Instruction.i32_const(value: reader.read_s32())
		0x42: webassembly.Instruction.i64_const(value: reader.read_s32())
		0x43: webassembly.Instruction.f32_const(value: reader.read_f32())
		0x44: webassembly.Instruction.f64_const(value: reader.read_f64())

		0x45: webassembly.Instruction.i32_eqz()
		0x46: webassembly.Instruction.i32_eq()
		0x47: webassembly.Instruction.i32_ne()
		0x48: webassembly.Instruction.i32_lt_s()
		0x49: webassembly.Instruction.i32_lt_u()
		0x4A: webassembly.Instruction.i32_gt_s()
		0x4B: webassembly.Instruction.i32_gt_u()
		0x4C: webassembly.Instruction.i32_le_s()
		0x4D: webassembly.Instruction.i32_le_u()
		0x4E: webassembly.Instruction.i32_ge_s()
		0x4F: webassembly.Instruction.i32_ge_u()

		0x50: webassembly.Instruction.i64_eqz()
		0x51: webassembly.Instruction.i64_eq()
		0x52: webassembly.Instruction.i64_ne()
		0x53: webassembly.Instruction.i64_lt_s()
		0x54: webassembly.Instruction.i64_lt_u()
		0x55: webassembly.Instruction.i64_gt_s()
		0x56: webassembly.Instruction.i64_gt_u()
		0x57: webassembly.Instruction.i64_le_s()
		0x58: webassembly.Instruction.i64_le_u()
		0x59: webassembly.Instruction.i64_ge_s()
		0x5A: webassembly.Instruction.i64_ge_u()

		0x5B: webassembly.Instruction.f32_eq()
		0x5C: webassembly.Instruction.f32_ne()
		0x5D: webassembly.Instruction.f32_lt()
		0x5E: webassembly.Instruction.f32_gt()
		0x5F: webassembly.Instruction.f32_le()
		0x60: webassembly.Instruction.f32_ge()

		0x61: webassembly.Instruction.f64_eq()
		0x62: webassembly.Instruction.f64_ne()
		0x63: webassembly.Instruction.f64_lt()
		0x64: webassembly.Instruction.f64_gt()
		0x65: webassembly.Instruction.f64_le()
		0x66: webassembly.Instruction.f64_ge()

		0x67: webassembly.Instruction.i32_clz()
		0x68: webassembly.Instruction.i32_ctz()
		0x69: webassembly.Instruction.i32_popcnt()
		0x6A: webassembly.Instruction.i32_add()
		0x6B: webassembly.Instruction.i32_sub()
		0x6C: webassembly.Instruction.i32_mul()
		0x6D: webassembly.Instruction.i32_div_s()
		0x6E: webassembly.Instruction.i32_div_u()
		0x6F: webassembly.Instruction.i32_rem_s()
		0x70: webassembly.Instruction.i32_rem_u()
		0x71: webassembly.Instruction.i32_and()
		0x72: webassembly.Instruction.i32_or()
		0x73: webassembly.Instruction.i32_xor()
		0x74: webassembly.Instruction.i32_shl()
		0x75: webassembly.Instruction.i32_shr_s()
		0x76: webassembly.Instruction.i32_shr_u()
		0x77: webassembly.Instruction.i32_rotl()
		0x78: webassembly.Instruction.i32_rotr()

		0x79: webassembly.Instruction.i64_clz()
		0x7A: webassembly.Instruction.i64_ctz()
		0x7B: webassembly.Instruction.i64_popcnt()
		0x7C: webassembly.Instruction.i64_add()
		0x7D: webassembly.Instruction.i64_sub()
		0x7E: webassembly.Instruction.i64_mul()
		0x7F: webassembly.Instruction.i64_div_s()
		0x80: webassembly.Instruction.i64_div_u()
		0x81: webassembly.Instruction.i64_rem_s()
		0x82: webassembly.Instruction.i64_rem_u()
		0x83: webassembly.Instruction.i64_and()
		0x84: webassembly.Instruction.i64_or()
		0x85: webassembly.Instruction.i64_xor()
		0x86: webassembly.Instruction.i64_shl()
		0x87: webassembly.Instruction.i64_shr_s()
		0x88: webassembly.Instruction.i64_shr_u()
		0x89: webassembly.Instruction.i64_rotl()
		0x8A: webassembly.Instruction.i64_rotr()

		0x8B: webassembly.Instruction.f32_abs()
		0x8C: webassembly.Instruction.f32_neg()
		0x8D: webassembly.Instruction.f32_ceil()
		0x8E: webassembly.Instruction.f32_floor()
		0x8F: webassembly.Instruction.f32_trunc()
		0x90: webassembly.Instruction.f32_nearest()
		0x91: webassembly.Instruction.f32_sqrt()
		0x92: webassembly.Instruction.f32_add()
		0x93: webassembly.Instruction.f32_sub()
		0x94: webassembly.Instruction.f32_mul()
		0x95: webassembly.Instruction.f32_div()
		0x96: webassembly.Instruction.f32_min()
		0x97: webassembly.Instruction.f32_max()
		0x98: webassembly.Instruction.f32_copysign()

		0x99: webassembly.Instruction.f64_abs()
		0x9A: webassembly.Instruction.f64_neg()
		0x9B: webassembly.Instruction.f64_ceil()
		0x9C: webassembly.Instruction.f64_floor()
		0x9D: webassembly.Instruction.f64_trunc()
		0x9E: webassembly.Instruction.f64_nearest()
		0x9F: webassembly.Instruction.f64_sqrt()
		0xA0: webassembly.Instruction.f64_add()
		0xA1: webassembly.Instruction.f64_sub()
		0xA2: webassembly.Instruction.f64_mul()
		0xA3: webassembly.Instruction.f64_div()
		0xA4: webassembly.Instruction.f64_min()
		0xA5: webassembly.Instruction.f64_max()
		0xA6: webassembly.Instruction.f64_copysign()

		0xA7: webassembly.Instruction.i32_wrap_i64()
		0xA8: webassembly.Instruction.i32_trunc_f32_s()
		0xA9: webassembly.Instruction.i32_trunc_f32_u()
		0xAA: webassembly.Instruction.i32_trunc_f64_s()
		0xAB: webassembly.Instruction.i32_trunc_f64_u()
		0xAC: webassembly.Instruction.i64_extend_i32_s()
		0xAD: webassembly.Instruction.i64_extend_i32_u()
		0xAE: webassembly.Instruction.i64_trunc_f32_s()
		0xAF: webassembly.Instruction.i64_trunc_f32_u()
		0xB0: webassembly.Instruction.i64_trunc_f64_s()
		0xB1: webassembly.Instruction.i64_trunc_f64_u()
		0xB2: webassembly.Instruction.f32_convert_i32_s()
		0xB3: webassembly.Instruction.f32_convert_i32_u()
		0xB4: webassembly.Instruction.f32_convert_i64_s()
		0xB5: webassembly.Instruction.f32_convert_i64_u()
		0xB6: webassembly.Instruction.f32_demote_f64()
		0xB7: webassembly.Instruction.f64_convert_i32_s()
		0xB8: webassembly.Instruction.f64_convert_i32_u()
		0xB9: webassembly.Instruction.f64_convert_i64_s()
		0xBA: webassembly.Instruction.f64_convert_i64_u()
		0xBB: webassembly.Instruction.f64_promote_f32()
		0xBC: webassembly.Instruction.i32_reinterpret_f32()
		0xBD: webassembly.Instruction.i64_reinterpret_f64()
		0xBE: webassembly.Instruction.f32_reinterpret_i32()
		0xBF: webassembly.Instruction.f64_reinterpret_i64()

		0xC0: webassembly.Instruction.i32_extend8_s()
		0xC1: webassembly.Instruction.i32_extend16_s()
		0xC2: webassembly.Instruction.i64_extend8_s()
		0xC3: webassembly.Instruction.i64_extend16_s()
		0xC4: webassembly.Instruction.i64_extend32_s()

		0xD0: webassembly.Instruction.ref_null(ty: read_heap_type(reader))
		0xD1: webassembly.Instruction.ref_is_null()
		0xD2: webassembly.Instruction.ref_func(funcidx: reader.read_u32())
		0xD4: webassembly.Instruction.ref_as_non_null()
		0xD3: webassembly.Instruction.ref_eq()

		0xFB:
			let t2 = reader.read_u32()
			switch t2:
				0: webassembly.Instruction.struct_new(ty: reader.read_u32())
				2:
					let ty = reader.read_u32()
					let field = reader.read_u32()
					webassembly.Instruction.struct_get(ty, field)
				5:
					let ty = reader.read_u32()
					let field = reader.read_u32()
					webassembly.Instruction.struct_set(ty, field)
				7: webassembly.Instruction.array_new_default(ty: reader.read_u32())
				8:
					let ty = reader.read_u32()
					let size = reader.read_u32()
					webassembly.Instruction.array_new_fixed(ty, size)
				9:
					let ty = reader.read_u32()
					let dataidx = reader.read_u32()
					webassembly.Instruction.array_new_data(ty, dataidx)
				10:
					let ty = reader.read_u32()
					let elemidx = reader.read_u32()
					webassembly.Instruction.array_new_elem(ty, elemidx)
				11: webassembly.Instruction.array_get(ty: reader.read_u32())
				14: webassembly.Instruction.array_set(ty: reader.read_u32())
				22: webassembly.Instruction.ref_cast(ty: webassembly.RefType(nullable: false, heap_type: read_heap_type(reader)))
				23: webassembly.Instruction.ref_cast(ty: webassembly.RefType(nullable: true, heap_type: read_heap_type(reader)))
				26: webassembly.Instruction.any_convert_extern()
				27: webassembly.Instruction.extern_convert_any()
				28: webassembly.Instruction.ref_i31()
				29: webassembly.Instruction.i31_get(signed: true)
				30: webassembly.Instruction.i31_get(signed: false)
			else:
				panic("Bad FB opcode: {t2}")
	else:
		panic("Bad opcode: {t}")

fn read_datas(reader: Reader, datas: List[webassembly.Data]):
	var count = reader.read_u32()
	while count > 0:
		count -= 1
		let skip = reader.read_byte()
		if skip != 1:
			panic("Only passive data supported")
		datas.append(webassembly.Data(data: read_blob(reader)))

fn read_blob(reader: Reader) -> Bytes:
	reader.read_bytes(size: reader.read_u32())

fn read_str(reader: Reader) -> str:
	bytes_to_ascii(data: read_blob(reader))

fn read_ref_type(reader: Reader, nullable: bool) -> webassembly.RefType:
	let heap_type = read_heap_type(reader)
	webassembly.RefType(nullable, heap_type)

class Reader:
	var m_reader: ByteReader

	pub fn at_end() -> bool:
		m_reader.at_end()

	pub fn peek_byte() -> int:
		m_reader.peek_byte(ahead: 0)

	pub fn skip_byte():
		let _drop = m_reader.read_byte()

	pub fn read_byte() -> int:
		m_reader.read_byte()

	pub fn read_u32() -> int:
		leb128.unpack_unsigned_leb128(reader: m_reader)

	pub fn read_s32() -> int:
		leb128.unpack_signed_leb128(reader: m_reader)

	pub fn read_f32() -> float32:
		panic("TODO:read_f32")

	pub fn read_f64() -> float64:
		panic("TODO:read_f64")

	pub fn read_bytes(size: int) -> Bytes:
		m_reader.read_bytes(size)

struct Section:
	id: int
	data: Bytes

fn read_section(reader: Reader) -> Section:
	let id = reader.read_byte()
	let data = read_blob(reader)
	Section(id, data)
