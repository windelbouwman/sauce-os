
from std import print, float_to_str
from strlib import str_repeat, str_join
from utils import panic, assert, log_info, log_error
from location import Location, location_default
from listtype import List
from optiontype import Option, option_unwrap, option_is_some
from vectype import Vector, new_vector_with_capacity, new_vector
from hashmap import HashMap, new_hashmap_str, new_hashmap, str_hash

# Name coupled with global unique ID:
pub struct NodeId:
	name: str
	id: int

fn node_id_equal(node_id1: NodeId, node_id2: NodeId) -> bool:
	if node_id1.id == node_id2.id:
		node_id1.name == node_id2.name
	else:
		false

pub fn node_id_to_string(id?: NodeId) -> str:
	"{id.name}${id.id}"

pub fn new_hashmap_nodeid[T]() -> HashMap[NodeId,T]:
	new_hashmap(f_hash: node_id_hash, f_eq: node_id_equal)

fn node_id_hash(a?: NodeId) -> int:
	str_hash(a.name) * 7919 + a.id

# TODO: implement type-defs!
pub class Type:
	pub var kind: TypeKind
	pub var was_generic: bool = false

	pub fn to_string() -> str:
		type_to_string(this)

	pub fn change_to(to_type: Type):
		change_type_to(ty: this, to_type)

	pub fn is_enum() -> bool:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Enum(x):
						true
				else:
					false
		else:
			false

	pub fn get_enum_def() -> EnumDef:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Enum(enum_def):
						enum_def
				else:
					panic("get_enum_def: type must be enum")
		else:
			panic("get_enum_def: type must be enum")

	pub fn get_enum_variant_from_type(attr: str) -> Option[EnumVariant]:
		let enum_def = get_enum_def()
		get_enum_variant(enum_def, attr)

	pub fn get_enum_variant_names() -> List[str]:
		let enum_def = get_enum_def()
		let names: List[str] = List()
		for variant in enum_def.variants:
			names.append(variant.name)
		names

	pub fn is_class() -> bool:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Class(x):
						true
				else:
					false
		else:
			false

	pub fn is_interface() -> bool:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Interface(interface_def):
						true
				else:
					false
		else:
			false

	pub fn is_int() -> bool:
		case kind:
			Base(base):
				case base:
					Int(signed, bits):
						true
				else:
					false
		else:
			false

	pub fn is_signed_int() -> bool:
		case kind:
			Base(base):
				case base:
					Int(signed, bits):
						signed
				else:
					false
		else:
			false

	pub fn get_bits() -> int:
		case kind:
			Base(base):
				case base:
					Int(signed, bits):
						bits
					Float(bits):
						bits
				else:
					panic("get_bits: Not an integer or float type")
		else:
			panic("get_bits: Not an integer or float type")

	pub fn is_void() -> bool:
		case kind:
			Void:
				true
		else:
			false

	pub fn is_unreachable() -> bool:
		case kind:
			Unreachable:
				true
		else:
			false

	pub fn is_undefined() -> bool:
		case kind:
			Undefined:
				true
		else:
			false

	pub fn is_str() -> bool:
		case kind:
			Base(base):
				case base:
					Str:
						true
				else:
					false
		else:
			false

	pub fn is_char() -> bool:
		case kind:
			Base(base):
				case base:
					Char:
						true
				else:
					false
		else:
			false

	pub fn is_bool() -> bool:
		case kind:
			Base(base):
				case base:
					Bool:
						true
				else:
					false
		else:
			false

	pub fn is_float() -> bool:
		case kind:
			Base(base):
				case base:
					Float(bits):
						true
				else:
					false
		else:
			false

	pub fn is_base_type() -> bool:
		case kind:
			Base(base):
				true
		else:
			false

	pub fn get_base_type() -> BaseType:
		case kind:
			Base(base):
				base
		else:
			panic("get_base_type: Not a base type")

	pub fn is_opaque() -> bool:
		case kind:
			Opaque:
				true
		else:
			false

	pub fn is_array() -> bool:
		case kind:
			Array(element_type, size):
				true
		else:
			false

	pub fn get_element_type() -> Type:
		case kind:
			Array(element_type, size):
				element_type
		else:
			panic("No array type")

	pub fn get_array_size() -> int:
		case kind:
			Array(element_type, size):
				size
		else:
			panic("No array type")

	pub fn is_struct() -> bool:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Struct(struct_def):
						true
				else:
					false
		else:
			false

	pub fn is_union_struct() -> bool:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Struct(struct_def):
						struct_def.is_union
				else:
					false
		else:
			false

	pub fn get_struct_def() -> StructDef:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Struct(struct_def):
						struct_def
				else:
					panic("No struct type")
		else:
			panic("No struct type")

	pub fn get_interface_def() -> InterfaceDef:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Interface(interface_def):
						interface_def
				else:
					panic("No interface type")
		else:
			panic("No interface type")

	pub fn has_field(attr: str) -> bool:
		option_is_some(maybe_get_field_type(attr, also_private: false))

	pub fn get_field_type(attr: str) -> Type:
		case maybe_get_field_type(attr, also_private: true):
			Some(ty):
				ty
			None:
				panic("No field: {attr}")

	pub fn maybe_get_field_type(attr: str, also_private: bool) -> Option[Type]:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Struct(struct_def):
						case struct_def.scope.lookup(name: attr):
							Some(sym):
								let m = create_subst_mapping(type_parameters: struct_def.type_parameters, type_arguments)
								case sym.kind:
									Field(f):
										Option.Some(subst(ty: f.ty, m))
								else:
									panic("Struct field must be ")
							None:
								Option.None()
					Class(class_def):
						case class_def.scope.lookup(name: attr):
							Some(sym):
								if sym.is_pub or also_private:
									let m = create_subst_mapping(type_parameters: class_def.type_parameters, type_arguments)
									let ty = case sym.kind:
										Function(function_def):
											subst(ty: get_function_type(function_def), m)
										Var(v):
											subst(ty: v.ty, m)
									else:
										panic("class must contain func/vars")
									Option.Some(ty)
								else:
									Option.None()
							None:
								Option.None()
					Interface(interface_def):
						case interface_def.scope.lookup(name: attr):
							Some(sym):
								if sym.is_pub or also_private:
									let m = create_subst_mapping(type_parameters: interface_def.type_parameters, type_arguments)
									let ty = case sym.kind:
										Function(function_def):
											subst(ty: get_function_type(function_def), m)
									else:
										panic("interface must contain only functionss")
									Option.Some(ty)
								else:
									Option.None()
							None:
								Option.None()
				else:
					Option.None()
		else:
			Option.None()

	pub fn get_field_types() -> Vector[Type]:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Struct(struct_def):
						let m = create_subst_mapping(type_parameters: struct_def.type_parameters, type_arguments)
						let field_types: Vector[Type] = new_vector_with_capacity(capacity: struct_def.fields.len())
						for field in struct_def.fields:
							field_types.append(subst(ty: field.ty, m))
						field_types
				else:
					panic("Type without fields")
		else:
			panic("Type without fields")

	pub fn has_method(name?: str) -> bool:
		if has_field(attr: name):
			get_field_type(attr: name).is_function_type()
		else:
			false

	pub fn is_sequence_like() -> bool:
		has_method("len") and has_method("get")

	pub fn is_iterable_like() -> bool:
		has_method("iter")

	pub fn is_nullable() -> bool:
		# TODO
		# false
		# is_struct() or is_enum() or is_type_parameter()
		is_type_parameter()

	pub fn is_function_type() -> bool:
		case kind:
			Function(p, i):
				true
		else:
			false

	pub fn get_parameter_types() -> Vector[ParameterType]:
		case kind:
			Function(p, i):
				p
		else:
			panic("Type must be function type")

	pub fn get_return_type() -> Type:
		case kind:
			Function(p, i):
				i.return_type
		else:
			panic("Type must be function type")

	pub fn get_except_type() -> Type:
		case kind:
			Function(p, i):
				i.except_type
		else:
			panic("Type must be function type")

	pub fn get_class_def() -> ClassDef:
		case kind:
			App(tycon, type_arguments):
				case tycon:
					Class(class_def):
						class_def
				else:
					panic("No class type")
		else:
			panic("No class type")

	pub fn is_tycon_app() -> bool:
		case kind:
			App(tycon, args):
				true
		else:
			false

	pub fn get_tycon() -> TyCon:
		case kind:
			App(tycon, args):
				tycon
		else:
			panic("Must be App type")

	pub fn get_type_arguments() -> Vector[Type]:
		case kind:
			App(tycon, args):
				args
		else:
			panic("Must be App type")

	pub fn is_type_parameter() -> bool:
		case kind:
			TypeParam(p):
				true
		else:
			false

	pub fn get_type_parameter() -> TypeParameter:
		case kind:
			TypeParam(p):
				p
		else:
			panic("Type must be type parameter")

	pub fn is_type_var() -> bool:
		case kind:
			TypeVar(v):
				true
		else:
			false

	pub fn get_type_var() -> TypeVariable:
		case kind:
			TypeVar(v):
				v
		else:
			panic("Type must be type variable reference")

fn clone_type(ty?: Type) -> Type:
	let ty2 = new_type(kind: ty.kind)
	ty2.was_generic = ty.was_generic
	ty2

pub fn new_type(kind: TypeKind) -> Type:
	Type(kind)

fn types_to_string(typs: Vector[Type]) -> str:
	let parts: List[str] = List()
	for ty in typs:
		parts.append(type_to_string(ty))
	"[" + str_join(parts, sep: ", ") + "]"

fn type_to_string(ty?: Type) -> str:
	let txt = type_kind_to_string(kind: ty.kind)

	if ty.was_generic:
		"@" + txt
	else:
		txt

fn change_type_to(ty: Type, to_type: Type):
	# Adjust ty to ty2
	ty.kind = to_type.kind
	# TBD: copy was generic?
	# ty.was_generic = ty.was_generic

pub fn apply_tycon(tycon: TyCon, type_arguments: Vector[Type]) -> Type:
	# if type_arguments
	let type_parameters = tycon_get_type_parameters(tycon)
	# Check lengths!
	# assert(condition: type_parameters.len() == type_arguments.len(), message: "type arguments does not match amount of type parameters")
	if not (type_parameters.len() == type_arguments.len()):
		assert(condition: false, message: "type arguments does not match amount of type parameters")
	new_type(kind: TypeKind.App(tycon, type_arguments))

pub fn subst(ty: Type, m: HashMap[str,Type]) -> Type:
	case ty.kind:
		TypeParam(p):
			case m.maybe_get(key: p.id.name):
				Some(ty3):
					# Idea is to record if we once were a type-parameter:
					let ty4 = clone_type(ty3)
					ty4.was_generic = true
					ty4
				None:
					ty
		Function(parameter_types, info):
			let parameter_types2: Vector[ParameterType] = new_vector_with_capacity(capacity: parameter_types.len())
			for p in parameter_types:
				parameter_types2.append(ParameterType(label: p.label, ty: subst(ty: p.ty, m)))
			let info2 = FunctionInfo:
				return_type: subst(ty: info.return_type, m)
				except_type: subst(ty: info.except_type, m)
			function_type(parameter_types: parameter_types2, info: info2)
		Array(element_type, size):
			element_type = subst(ty: element_type, m)
			array_type(element_type, size)
		Pointer(pointed_type):
			pointed_type = subst(ty: pointed_type, m)
			pointer_type(pointed_type)
		App(tycon, type_arguments):
			apply_tycon(tycon, type_arguments: subst_many(typs: type_arguments, m))
	else:
		ty

fn subst_many(typs: Vector[Type], m: HashMap[str,Type]) -> Vector[Type]:
	let typs2: Vector[Type] = new_vector_with_capacity(capacity: typs.len())
	for ty in typs:
		typs2.append(subst(ty, m))
	typs2

pub fn create_subst_mapping(type_parameters: List[TypeParameter], type_arguments: Vector[Type]) -> HashMap[str,Type]:
	if type_parameters.len() != type_arguments.len():
		for type_parameter in type_parameters:
			log_error("type parameter: {node_id_to_string(type_parameter.id)}")
		for type_argument in type_arguments:
			log_error("type argument: {type_argument}")
		panic("amount of type parameters and type arguments must be equal")
	let m: HashMap[str,Type] = new_hashmap_str()
	let tpi = type_parameters.iter()
	for ty in type_arguments:
		let tp = option_unwrap(tpi.next())
		m.insert(key: tp.id.name, value: ty)
	m


pub fn is_some_integer_type(ty?: Type) -> bool:
	case ty.kind:
		SomeInteger(bits):
			true
	else:
		false

pub fn get_bits_from_some_integer_type(ty?: Type) -> int:
	case ty.kind:
		SomeInteger(bits):
			bits
	else:
		panic("get_bits_from_some_integer_type: Not a some-integer type")

pub fn deref_type_var(ty?: Type) -> Type:
	case ty.kind:
		TypeVar(type_var):
			case type_var.ty:
				None:
					panic("Must be assigned type!")
				Some(t):
					t = clone_type(t)
					t.was_generic = ty.was_generic
					t
	else:
		ty

pub fn get_types_from_parameter_types(p2?: Vector[ParameterType]) -> Vector[Type]:
	let t: Vector[Type] = new_vector_with_capacity(capacity: p2.len())
	for p in p2:
		t.append(p.ty)
	t

pub fn get_enum_variant(enum_def: EnumDef, attr: str) -> Option[EnumVariant]:
	case enum_def.scope.lookup(name: attr):
		Some(symbol):
			case symbol.kind:
				Variant(v):
					Option.Some(v)
			else:
				# panic("get_enum_variant: symbol must be ")
				Option.None()
		None:
			Option.None()

fn get_subst_map(ty: Type) -> HashMap[str,Type]:
	case ty.kind:
		App(tycon, type_arguments):
			create_subst_mapping(type_parameters: tycon_get_type_parameters(tycon), type_arguments)
	else:
		panic("Must be App type")

pub fn get_variant_payload_types(ty: Type, variant: EnumVariant) -> Vector[Type]:
	let m = get_subst_map(ty)
	subst_many(typs: variant.payload, m)

pub fn get_struct_field_index(ty: Type, attr: str) -> int:
	let struct_def = ty.get_struct_def()
	var index = 0
	for field in struct_def.fields:
		if field.name == attr:
			return index
		index += 1
	panic("No attr: {attr}")

pub fn get_method_ref_from_type(ty: Type, attr: str, location: Location) -> Expression:
	case ty.kind:
		App(tycon, type_arguments):
			case tycon:
				Class(c):
					let sym = option_unwrap(c.scope.lookup(name: attr))
					case sym.kind:
						Function(function_def):
							function_ref(function_def, type_arguments, location)
					else:
						panic("get_method_ref_from_type: class must contain func/vars")
			else:
				panic("get_method_ref_from_type: No class: {ty}")
	else:
		panic("get_method_ref_from_type: No class: {ty}")

pub struct QualName:
	location: Location
	parts: List[str]

# enum QualPart:
#     Name(name: str)
#     Based(base: QualName, attr: str)

pub fn qual_name_to_string(name: QualName) -> str:
	str_join(parts: name.parts, sep: "::")

pub enum TypeKind:
	Base(base: BaseType)
	Undefined
	SomeInteger(bits: int)  # Integer type, requiring at least n bits
	Opaque
	Void
	Unreachable
	NameRef(name: QualName)
	Function(parameter_types: Vector[ParameterType], info: FunctionInfo)
	TypeParam(type_parameter: TypeParameter)
	TypeVar(type_variable: TypeVariable)
	Array(element_type: Type, size: int)
	Pointer(pointed_type: Type)

	# Application of a type-constructor:
	UnApp(tycon: TyCon)
	App(tycon: TyCon, type_arguments: Vector[Type])

	Def(type_def: TypeDef)

fn type_kind_to_string(kind: TypeKind) -> str:
	case kind:
		Base(base):
			base_type_to_str(base)
		SomeInteger(bits):
			"SOME-INT-{bits}"
		Opaque:
			"OPAQUE"
		Void:
			"VOID"
		Unreachable:
			"UNREACHABLE-TYPE"
		NameRef(name):
			"QualName({qual_name_to_string(name)})"
		Array(element_type, size):
			"ARRAY({element_type} x {size})"
		Pointer(pointed_type):
			"PTR({pointed_type})"
		Function(parameter_types, info):
			let typs = get_types_from_parameter_types(parameter_types)
			"FUNC-TYPE({types_to_string(typs)},{info.return_type},{info.except_type})"
		Undefined:
			"UNDEFINED"
		TypeParam(param):
			"TYPE-PARAM({node_id_to_string(param.id)})"
		TypeVar(v):
			case v.ty:
				None:
					"TYPE-VAR(id={v.unique})"
				Some(ty_assigned):
					"TYPE-VAR(id={v.unique},{ty_assigned})"
		UnApp(tycon):
			"UnApp({tycon_to_str(tycon)})"
		App(tycon, type_arguments):
			if type_arguments.is_empty():
				tycon_to_str(tycon)
			else:
				let args = types_to_string(typs: type_arguments)
				tycon_to_str(tycon) + args
		Def(type_def):
			type_def_to_str(type_def)

pub struct ParameterType:
	label: Option[str]
	ty: Type

enum BaseType:
	Bool
	Int(signed: bool, bits: int)
	Str
	Char
	Float(bits: int)

fn base_type_to_str(base: BaseType) -> str:
	case base:
		Str:
			"STR"
		Char:
			"CHAR"
		Int(signed, bits):
			if signed:
				"Int{bits}"
			else:
				"Uint{bits}"
		Bool:
			"BOOL"
		Float(bits):
			"FLOAT{bits}"

pub fn base_type_equal(base_type1: BaseType, base_type2: BaseType) -> bool:
	case base_type1:
		Str:
			case base_type2:
				Str:
					true
			else:
				false
		Char:
			case base_type2:
				Char:
					true
			else:
				false
		Int(signed1, bits1):
			case base_type2:
				Int(signed2, bits2):
					(signed1 == signed2) and (bits1 == bits2)
			else:
				false
		Bool:
			case base_type2:
				Bool:
					true
			else:
				false
		Float(bits1):
			case base_type2:
				Float(bits2):
					bits1 == bits2
			else:
				false

pub struct TypeVariable:
	unique: int
	ty: Option[Type]  # assigned type

pub enum TyCon:
	Struct(struct_def: StructDef)
	Enum(enum_def: EnumDef)
	Class(class_def: ClassDef)
	Interface(interface_def: InterfaceDef)
	Ref(key: NodeId)
	NameRef(name: QualName)

fn tycon_to_str(tycon: TyCon) -> str:
	case tycon:
		Struct(struct_def):
			struct_def_to_str(struct_def)
		Enum(enum_def):
			enum_def_to_str(enum_def)
		Class(class_def):
			class_def_to_str(class_def)
		Interface(interface_def):
			"tycon-interface"
		Ref(key):
			"tycon-ref-{node_id_to_string(key)}"
		NameRef(name):
			"tycon-name-ref-{qual_name_to_string(name)}"

pub fn tycon_equal(tycon1: TyCon, tycon2: TyCon) -> bool:
	case tycon1:
		Struct(struct_def1):
			case tycon2:
				Struct(struct_def2):
					node_id_equal(node_id1: struct_def1.id, node_id2: struct_def2.id)
			else:
				false
		Enum(enum_def1):
			case tycon2:
				Enum(enum_def2):
					node_id_equal(node_id1: enum_def1.id, node_id2: enum_def2.id)
			else:
				false
		Class(class_def1):
			case tycon2:
				Class(class_def2):
					node_id_equal(node_id1: class_def1.id, node_id2: class_def2.id)
			else:
				false
		Interface(interface_def1):
			case tycon2:
				Interface(interface_def2):
					node_id_equal(node_id1: interface_def1.id, node_id2: interface_def2.id)
			else:
				false
		Ref(key):
			false
		NameRef(name):
			false

pub fn tycon_get_type_parameters(tycon: TyCon) -> List[TypeParameter]:
	case tycon:
		Struct(struct_def):
			struct_def.type_parameters
		Enum(enum_def):
			enum_def.type_parameters
		Class(class_def):
			class_def.type_parameters
		Interface(interface_def):
			interface_def.type_parameters
		Ref(key):
			panic("reference has no type parameters")
		NameRef(key):
			panic("name-reference has no type parameters")

pub fn void_type() -> Type:
	new_type(kind: TypeKind.Void())

pub fn unreachable_type() -> Type:
	new_type(kind: TypeKind.Unreachable())

fn new_base_type(base: BaseType) -> Type:
	new_type(kind: TypeKind.Base(base))

pub fn bool_type() -> Type:
	new_base_type(base: BaseType.Bool())

pub fn int_type() -> Type:
	int64_type()

pub fn specific_int_type(signed: bool, bits: int) -> Type:
	new_base_type(base: BaseType.Int(signed, bits))

pub fn uint8_type() -> Type:
	specific_int_type(signed: false, bits: 8)

pub fn uint16_type() -> Type:
	specific_int_type(signed: false, bits: 16)

pub fn uint32_type() -> Type:
	specific_int_type(signed: false, bits: 32)

pub fn uint64_type() -> Type:
	specific_int_type(signed: false, bits: 64)

pub fn int8_type() -> Type:
	specific_int_type(signed: true, bits: 8)

pub fn int16_type() -> Type:
	specific_int_type(signed: true, bits: 16)

pub fn int32_type() -> Type:
	specific_int_type(signed: true, bits: 32)

pub fn int64_type() -> Type:
	specific_int_type(signed: true, bits: 64)

pub fn float_type() -> Type:
	float64_type()

pub fn specific_float_type(bits: int) -> Type:
	new_base_type(base: BaseType.Float(bits))

pub fn float32_type() -> Type:
	specific_float_type(bits: 32)

pub fn float64_type() -> Type:
	specific_float_type(bits: 64)

pub fn str_type() -> Type:
	new_base_type(base: BaseType.Str())

pub fn char_type() -> Type:
	new_base_type(base: BaseType.Char())

# Opaque type, void*
pub fn opaque_type() -> Type:
	new_type(kind: TypeKind.Opaque())

pub fn undefined_type() -> Type:
	new_type(kind: TypeKind.Undefined())

fn pointer_type(pointed_type: Type) -> Type:
	new_type(kind: TypeKind.Pointer(pointed_type))

pub fn array_type(element_type: Type, size: int) -> Type:
	new_type(kind: TypeKind.Array(element_type, size))

pub fn function_type(parameter_types: Vector[ParameterType], info: FunctionInfo) -> Type:
	new_type(kind: TypeKind.Function(parameter_types, info))

pub fn type_parameter_ref(type_parameter: TypeParameter) -> Type:
	new_type(kind: TypeKind.TypeParam(type_parameter))

pub fn new_type_var_ref(type_var: TypeVariable) -> Type:
	new_type(kind: TypeKind.TypeVar(type_var))

pub fn new_type_var(unique: int) -> TypeVariable:
	TypeVariable(unique, ty: Option.None())

pub fn type_var_equals(type_var1: TypeVariable, type_var2: TypeVariable) -> bool:
	type_var1.unique == type_var2.unique

pub struct ModuleSet:
	modules: List[ModuleDef]

pub class ModuleDef:
	pub var name: str
	pub var location: Location
	pub var filename: Option[str]
	pub var imports: Vector[Import]
	pub var definitions: List[Definition]
	pub var scope: Scope

	fn define_symbol(name: str, definition: Definition):
		definitions.append(definition)

	pub fn define_function(function_def: FunctionDef):
		define_symbol(name: function_def.name, definition: Definition.Function(function_def))

	pub fn add_module(m?: ModuleDef):
		definitions.append(Definition.Module(m))

pub fn new_module(name: str, location: Location, filename: Option[str], imports: Vector[Import], definitions: List[Definition]) -> ModuleDef:
	ModuleDef:
		name
		location
		filename
		imports
		definitions
		scope: Scope()

pub fn new_empty_module(name: str, location: Location) -> ModuleDef:
	new_module:
		name
		location
		filename: Option.None()
		imports: new_vector()
		definitions: List()

pub fn import_self(modname: str, location: Location) -> Import:
	Import:
		modname: modname
		location: location
		kind: ImportKind.Self()

pub fn import_names(modname: str, location: Location, names: List[NameAtLocation]) -> Import:
	Import:
		modname: modname
		location: location
		kind: ImportKind.Names(names)

pub struct Import:
	modname: str
	location: Location
	kind: ImportKind

pub enum ImportKind:
	Self
	Names(names: List[NameAtLocation])

pub struct NameAtLocation:
	name: str
	location: Location

pub fn extern_function_def(is_pub: bool, libname: str, name: str, docstring: Option[str], type_parameters: List[TypeParameter], parameters: List[ParameterDef], return_type: Type, location: Location) -> FunctionDef:
	let info = FunctionInfo:
		return_type
		except_type: void_type()

	FunctionDef:
		name
		docstring
		is_pub
		info
		type_parameters
		this_parameter: Option.None()
		parameters
		location
		body: FunctionDefBody.Extern(libname)

pub class Scope:
	var symbols: HashMap[str,Symbol] = new_hashmap_str()
	pub var class_scope: bool = false

	pub fn define(is_pub: bool, name: str, kind: SymbolKind, location: Location):
		let symbol = Symbol(is_pub, name, kind, location)
		symbols.insert(key: name, value: symbol)

	pub fn is_defined(name: str) -> bool:
		# Check if given name is defined.
		option_is_some(lookup(name))

	pub fn lookup(name: str) -> Option[Symbol]:
		symbols.maybe_get(key: name)

	fn dump():
		log_info("Scope:")
		for name in symbols:
			log_info(" - {name}")

	pub fn get_symbols() -> List[Symbol]:
		symbols.values()

pub enum SymbolKind:
	Module(module: ModuleDef)
	Macro(macro_def: MacroDef)
	Function(function_def: FunctionDef)
	Parameter(parameter_def: ParameterDef)
	Var(variable: Variable)
	TypeConstructor(tycon: TyCon)
	Typ(typ: Type)
	Variant(enum_variant: EnumVariant)
	Field(struct_field: StructField)

pub class Symbol:
	pub var is_pub: bool
	pub var name: str
	pub var kind: SymbolKind
	pub var location: Location
	var references: List[Location] = List()

	pub fn add_reference(location: Location):
		""" Register a reference this symbol """
		references.append(location)

	pub fn get_references() -> int:
		references.len()

	pub fn to_string() -> str:
		case kind:
			Module(module):
				"mod:{module.name}"
			Macro(macro_def):
				macro_def_to_str(macro_def)
			Function(function_def):
				function_def_to_str(function_def)
			Parameter(parameter):
				"parameter:{node_id_to_string(parameter.id)}"
			Var(variable):
				"var:{node_id_to_string(variable.id)}"
			TypeConstructor(t):
				"tycon"
			Typ(t):
				"typ"
			Variant(v):
				"EnumVariant({v.name})"
			Field(field):
				"Field({field.name})"

pub enum Definition:
	Module(module: ModuleDef)
	Macro(macro_def: MacroDef)
	Function(function_def: FunctionDef)
	Enum(enum_def: EnumDef)
	Struct(struct_def: StructDef)
	Class(class_def: ClassDef)
	Interface(interface_def: InterfaceDef)
	Impl(impl_df: ImplDef)
	Var(var_def: VariableDef)
	Type(type_def: TypeDef)

pub fn definition_to_str(definition: Definition) -> str:
	case definition:
		Module(module):
			"mod:{module.name}"
		Macro(macro_def):
			macro_def_to_str(macro_def)
		Function(function_def):
			function_def_to_str(function_def)
		Enum(enum_def):
			enum_def_to_str(enum_def)
		Struct(struct_def):
			struct_def_to_str(struct_def)
		Class(class_def):
			class_def_to_str(class_def)
		Interface(interface_def):
			"Interface"
		Impl(impl_def):
			"Impl"
		Var(variable_def):
			variable_def_to_str(variable_def)
		Type(type_def):
			type_def_to_str(type_def)

pub struct MacroDef:
	name: str
	location: Location

fn macro_def_to_str(macro_def: MacroDef) -> str:
	"Macro({macro_def.name})"

pub struct VariableDef:
	is_pub: bool
	variable: Variable
	value: VariableDefValue

pub enum VariableDefValue:
	Intern(value: Option[Expression])
	Extern(libname: str, initialized: bool)

fn variable_def_to_str(variable_def: VariableDef) -> str:
	"var-def:{node_id_to_string(variable_def.variable.id)}"

pub fn new_type_parameter(name: str, id: int, location: Location) -> TypeParameter:
	TypeParameter(id: NodeId(name, id), location)

pub fn type_parameter_equals(tp1: TypeParameter, tp2: TypeParameter) -> bool:
	node_id_equal(node_id1: tp1.id, node_id2: tp2.id)

pub struct TypeParameter:
	id: NodeId
	location: Location

pub fn struct_def(is_pub: bool, name: str, id: int, docstring: Option[str], type_parameters: List[TypeParameter], fields: List[StructField], location: Location) -> StructDef:
	StructDef:
		is_pub
		id: NodeId(name, id)
		docstring
		is_union: false
		type_parameters: type_parameters
		fields: fields
		location: location
		scope: Scope()

pub struct StructDef:
	is_pub: bool
	id: NodeId
	docstring: Option[str]
	is_union: bool
	type_parameters: List[TypeParameter]
	fields: List[StructField]
	location: Location
	scope: Scope

fn struct_def_to_str(struct_def: StructDef) -> str:
	let t = "Union" if struct_def.is_union else "Struct"
	"{t}({node_id_to_string(struct_def.id)})"

pub class StructBuilder:
	var nodeId: NodeId = NodeId(name: "", id: 0)
	var is_pub: bool = true
	var is_union: bool = false
	var location: Location = location_default()
	var type_parameters: List[TypeParameter] = List()
	var fields: List[StructField] = List()

	pub fn set_name(name: str):
		nodeId.name = name

	pub fn set_id(id?: int):
		nodeId.id = id

	pub fn set_pub(is_pub?: bool):
		this.is_pub = is_pub

	pub fn set_is_union(is_union?: bool):
		this.is_union = is_union

	pub fn add_type_parameter(name: str, id: int, location: Location) -> Type:
		let type_parameter = new_type_parameter(name, id, location)
		type_parameters.append(type_parameter)
		type_parameter_ref(type_parameter)

	pub fn add_field(name: str, ty: Type, location: Location):
		fields.append(StructField(name, ty, location))

	pub fn finish() -> StructDef:
		let scope = Scope()
		for field in fields:
			scope.define(is_pub: true, name: field.name, kind: SymbolKind.Field(field), location)
		StructDef:
			is_pub: is_pub
			id: nodeId
			docstring: Option.None()
			is_union: is_union
			type_parameters: type_parameters
			fields: fields
			location: location
			scope

pub struct StructField:
	name: str
	ty: Type
	location: Location

pub fn enum_def(is_pub: bool, name: str, id: int, docstring: Option[str], location: Location, type_parameters: List[TypeParameter], variants: List[EnumVariant]) -> EnumDef:
	EnumDef:
		is_pub
		id: NodeId(name, id)
		docstring
		location: location
		type_parameters: type_parameters
		variants: variants
		scope: Scope()

pub struct EnumDef:
	is_pub: bool
	id: NodeId
	docstring: Option[str]
	location: Location
	type_parameters: List[TypeParameter]
	variants: List[EnumVariant]
	scope: Scope

fn enum_def_to_str(enum_def: EnumDef) -> str:
	"enum({node_id_to_string(enum_def.id)})"

pub struct EnumVariant:
	name: str
	tag_value: int
	location: Location
	payload: Vector[Type]

pub struct ClassDef:
	is_pub: bool
	id: NodeId
	docstring: Option[str]
	location: Location
	is_extern: Option[str]
	type_parameters: List[TypeParameter]
	definitions: List[Definition]
	scope: Scope

fn class_def_to_str(class_def: ClassDef) -> str:
	"class({node_id_to_string(class_def.id)})"

pub struct InterfaceDef:
	is_pub: bool
	id: NodeId
	type_parameters: List[TypeParameter]
	docstring: Option[str]
	location: Location
	is_extern: Option[str]
	definitions: List[Definition]
	scope: Scope

pub struct ImplDef:
	id: NodeId
	interface_type: Type
	target_type: Type
	docstring: Option[str]
	location: Location
	definitions: List[Definition]
	scope: Scope

pub struct TypeDef:
	is_pub: bool
	id: NodeId
	ty: Type
	location: Location

fn type_def_to_str(type_def: TypeDef) -> str:
	"typedef-{node_id_to_string(type_def.id)}:{type_def.ty}"

pub fn function_def(is_pub: bool, name: str, docstring: Option[str], type_parameters: List[TypeParameter], this_parameter: Option[ParameterDef], parameters: List[ParameterDef], return_type: Type, except_type: Type, body: Statement, location: Location) -> FunctionDef:
	let info = FunctionInfo:
		return_type
		except_type

	FunctionDef:
		name
		docstring
		is_pub
		info
		type_parameters
		this_parameter
		parameters
		location
		body: FunctionDefBody.Intern(scoped_block: scoped_block(body))

pub struct FunctionInfo:
	return_type: Type
	except_type: Type

pub struct FunctionDef:
	# modname: str
	name: str
	docstring: Option[str]
	# id: NodeId
	is_pub: bool
	info: FunctionInfo
	type_parameters: List[TypeParameter]
	this_parameter: Option[ParameterDef]
	parameters: List[ParameterDef]
	body: FunctionDefBody
	location: Location

enum FunctionDefBody:
	Intern(body?: ScopedBlock)
	Extern(libname: str)
	None


pub fn function_decl_def(name: str, type_parameters: List[TypeParameter], this_parameter: Option[ParameterDef], parameters: List[ParameterDef], return_type: Type, except_type: Type, location: Location) -> FunctionDef:
	let info = FunctionInfo:
		return_type
		except_type
	let is_pub = true
	let docstring: Option[str] = Option.None()

	FunctionDef:
		name
		docstring
		is_pub
		info
		type_parameters
		this_parameter
		parameters
		location
		body: FunctionDefBody.None()

pub fn function_def_to_str(function_def: FunctionDef) -> str:
	"function:{function_def.name}"

pub fn function_ref(function_def: FunctionDef, type_arguments: Vector[Type], location: Location) -> Expression:
	let kind = ExpressionKind.FunctionRef(function_def, type_arguments)
	let ty = get_function_type2(function_def, type_arguments)
	Expression(kind, ty, location)

fn get_parameter_types_from_parameters(parameters: List[ParameterDef]) -> Vector[ParameterType]:
	let parameter_types: Vector[ParameterType] = new_vector_with_capacity(capacity: parameters.len())
	for parameter in parameters:
		let label: Option[str] = if parameter.label_is_optional:
			Option.None()
		else:
			Option.Some(parameter.id.name)
		parameter_types.append(ParameterType(label, ty: parameter.ty))
	parameter_types

fn get_function_type(function_def: FunctionDef) -> Type:
	assert(condition: function_def.type_parameters.is_empty(), message: "Get function type can only be used on a non-generic function")
	let parameter_types = get_parameter_types_from_parameters(parameters: function_def.parameters)
	function_type(parameter_types, info: function_def.info)

pub fn get_function_type2(function_def: FunctionDef, type_arguments: Vector[Type]) -> Type:
	let parameter_types = get_parameter_types_from_parameters(parameters: function_def.parameters)
	get_function_type3(type_parameters: function_def.type_parameters, type_arguments, parameter_types, info: function_def.info)

fn get_function_type3(type_parameters: List[TypeParameter], type_arguments: Vector[Type], parameter_types: Vector[ParameterType], info: FunctionInfo) -> Type:
	if type_parameters.is_empty():
		if not type_arguments.is_empty():
			panic(message: "type_arguments non empty, while type_parameters is empty")
		function_type(parameter_types, info)
	else:
		let m = create_subst_mapping(type_parameters, type_arguments)

		let parameter_types2: Vector[ParameterType] = new_vector_with_capacity(capacity: parameter_types.len())
		for pt in parameter_types:
			parameter_types2.append(ParameterType(label: pt.label, ty: subst(ty: pt.ty, m)))

		let info2 = FunctionInfo:
			return_type: subst(ty: info.return_type, m)
			except_type: subst(ty: info.except_type, m)
		function_type(parameter_types: parameter_types2, info: info2)

pub fn parameter_def(name: str, id: int, label_is_optional: bool, ty: Type, location: Location) -> ParameterDef:
	ParameterDef(id: NodeId(name, id), label_is_optional, ty, location)

pub class ParameterDef:
	pub var id: NodeId
	pub var label_is_optional: bool
	pub var ty: Type
	pub var location: Location

	pub fn ref(location: Location) -> Expression:
		parameter_ref(parameter_def: this, location)

pub fn unlabeled_parameter(name: str, ty: Type) -> ParameterDef:
	parameter_def(name, id: 0, label_is_optional: true, ty, location: location_default())

pub fn labeled_parameter(name: str, ty: Type) -> ParameterDef:
	parameter_def(name, id: 0, label_is_optional: false, ty, location: location_default())

pub fn variable(name: str, id: int, ty: Type, location: Location) -> Variable:
	Variable(id: NodeId(name, id), ty, location)

pub class Variable:
	pub var id: NodeId
	pub var ty: Type
	pub var location: Location
	pub var writable: bool = false

	pub fn ref(location: Location) -> Expression:
		variable_ref(variable: this, location)

pub struct ScopedBlock:
	scope: Scope
	body: Statement

pub fn scoped_block(body: Statement) -> ScopedBlock:
	ScopedBlock(scope: Scope(), body)

pub class Statement:
	pub var kind: StatementKind
	pub var location: Location
	pub var ty: Type

	pub fn to_string() -> str:
		statement_to_string(statement: this)

	pub fn is_breakable() -> bool:
		""" Can we use break / continue within this statement? """
		case kind:
			While(x):
				true
			Loop(x):
				true
			For(x):
				true
		else:
			false

	pub fn last_is_expr() -> bool:
		""" Determine if the last statement is an expression """
		case kind:
			Expr(e):
				true
			Compound(inner):
				inner.last().last_is_expr()
		else:
			false

fn statement(kind: StatementKind, location: Location) -> Statement:
	let ty = void_type()
	Statement(kind, location, ty)

pub enum StatementKind:
	If(if_statement: IfStatement)
	While(while_statement: WhileStatement)
	Loop(loop_statement: LoopStatement)
	For(for_statement: ForStatement)
	Case(case_statement: CaseStatement)
	Switch(switch_statement: SwitchStatement)
	Let(let_statement: LetStatement)
	Try(try_statement: TryStatement)
	Compound(body: Vector[Statement])
	Expr(expression: Expression)
	Assignment(target: Expression, operator: Option[BinaryOperator], value: Expression)
	Return(value: Option[Expression])
	Raise(value: Expression)
	Unreachable
	Pass
	Break
	Continue



pub fn if_statement(condition: Expression, body: Statement, false_body: Statement, location: Location) -> Statement:
	let if_statement = IfStatement:
		condition: condition
		true_block: scoped_block(body)
		false_block: scoped_block(body: false_body)

	let kind = StatementKind.If(if_statement)
	statement(kind, location)

pub struct IfStatement:
	condition: Expression
	true_block: ScopedBlock
	false_block: ScopedBlock

pub struct WhileStatement:
	condition: Expression
	block: ScopedBlock

pub fn while_statement(condition: Expression, body: Statement, location: Location) -> Statement:
	let while_statement = WhileStatement:
		condition
		block: scoped_block(body)
	let kind = StatementKind.While(while_statement)
	statement(kind, location)

pub fn loop_statement(body: Statement, location: Location) -> Statement:
	let block = scoped_block(body)
	let kind = StatementKind.Loop(loop_statement: LoopStatement(block))
	statement(kind, location)

struct LoopStatement:
	block: ScopedBlock

pub fn for_statement(iter_var: Variable, iter_value: Expression, body: Statement, location: Location) -> Statement:
	let for_statement = ForStatement:
		iter_var
		iter_value
		block: scoped_block(body)
	statement(kind: StatementKind.For(for_statement), location)

pub struct ForStatement:
	iter_var: Variable
	iter_value: Expression
	block: ScopedBlock

pub fn try_statement(try_body: Statement, except_var: Variable, except_type: Type, except_body: Statement, location: Location) -> Statement:
	let try_statement = TryStatement:
		try_block: scoped_block(body: try_body)
		except_var
		except_type
		except_block: scoped_block(body: except_body)
	statement(kind: StatementKind.Try(try_statement), location)

pub struct TryStatement:
	try_block: ScopedBlock
	except_var: Variable
	except_type: Type
	except_block: ScopedBlock

pub fn case_statement(value: Expression, arms: List[CaseArm], else_clause: Option[Statement], location: Location) -> Statement:
	let else_block: Option[ScopedBlock] = case else_clause:
		Some(body):
			Option.Some(scoped_block(body))
		None:
			Option.None()
	let case_statement = CaseStatement(value, arms, else_block)
	statement(kind: StatementKind.Case(case_statement), location)

pub struct CaseStatement:
	value: Expression
	arms: List[CaseArm]
	else_block: Option[ScopedBlock]

pub struct CaseArm:
	location: Location
	name: str
	variables: List[Variable]
	block: ScopedBlock

pub fn switch_statement(value: Expression, arms: List[SwitchArm], default_body: Statement, location: Location) -> Statement:
	let default_block = scoped_block(body: default_body)
	let switch_statement = SwitchStatement(value, arms, default_block)
	statement(kind: StatementKind.Switch(switch_statement), location)

pub struct SwitchStatement:
	value: Expression
	arms: List[SwitchArm]
	default_block: ScopedBlock

pub struct SwitchArm:
	location: Location
	value: Expression
	block: ScopedBlock

pub fn let_statement(variable: Variable, type_hint: Option[Type], value: Expression, location: Location) -> Statement:
	let let_statement = LetStatement(variable, type_hint, value)
	let kind = StatementKind.Let(let_statement)
	statement(kind, location)

struct LetStatement:
	variable: Variable
	type_hint: Option[Type]
	value: Expression

pub fn compound(inner: Vector[Statement], location: Location) -> Statement:
	if inner.len() == 1:
		inner[0]
	else:
		let kind = StatementKind.Compound(body: inner)
		statement(kind, location)

pub fn expression_statement(expr: Expression) -> Statement:
	let kind = StatementKind.Expr(expr)
	statement(kind, location: expr.location)

pub fn assignment_statement(target: Expression, op: Option[BinaryOperator], value: Expression, location: Location) -> Statement:
	let kind = StatementKind.Assignment(target, op, value)
	statement(kind, location)

pub fn return_statement(value: Option[Expression], location: Location) -> Statement:
	statement(kind: StatementKind.Return(value), location)

pub fn raise_statement(value: Expression, location: Location) -> Statement:
	statement(kind: StatementKind.Raise(value), location)

pub fn pass_statement(location: Location) -> Statement:
	statement(kind: StatementKind.Pass(), location)

pub fn break_statement(location: Location) -> Statement:
	statement(kind: StatementKind.Break(), location)

pub fn continue_statement(location: Location) -> Statement:
	statement(kind: StatementKind.Continue(), location)

pub fn unreachable_statement(location: Location) -> Statement:
	statement(kind: StatementKind.Unreachable(), location)

pub class Expression:
	pub var kind: ExpressionKind
	pub var ty: Type
	pub var location: Location
	pub var writable: bool = false

	pub fn to_string() -> str:
		expression_to_string(this)

	pub fn is_this() -> bool:
		""" Check if the expression is a reference to the 'this' parameter """
		case kind:
			ParameterRef(parameter):
				parameter.id.name == "this"
		else:
			false

	pub fn call_method(method: str, arguments: List[LabeledExpression], location: Location) -> Expression:
		let callee = get_attr_typed(attr: method, location)
		let result_ty: Type = callee.ty.get_return_type()
		call(callee, arguments, ty: result_ty, location)

	pub fn call_it(arguments: List[LabeledExpression], location: Location) -> Expression:
		let return_type = ty.get_return_type()
		call(callee: this, arguments, ty: return_type, location)

	pub fn add(rhs: Expression, location: Location) -> Expression:
		binop(lhs: this, op: BinaryOperator.Add(), rhs, ty, location)

	pub fn less(rhs: Expression, location: Location) -> Expression:
		binop(lhs: this, op: BinaryOperator.Less(), rhs, ty: bool_type(), location)

	pub fn equals(rhs: Expression, location: Location) -> Expression:
		binop(lhs: this, op: BinaryOperator.Equals(), rhs, ty: bool_type(), location)

	pub fn get_attr_typed(attr: str, location: Location) -> Expression:
		let attr_ty = ty.get_field_type(attr)
		get_attr(base: this, field: attr, ty: attr_ty, location)

	pub fn change_to(to: Expression):
		change_expression_to(expression: this, to)

pub fn clone_expression(value: Expression) -> Expression:
	Expression(kind: value.kind, ty: value.ty, location: value.location)

fn change_expression_to(expression: Expression, to: Expression):
	expression.kind = to.kind
	expression.ty = to.ty

pub enum ExpressionKind:
	Call(call: FunctionCall)
	GetAttr(base: Expression, name: str)
	GetIndex(base: Expression, indici: List[Expression])
	Binop(binop: BinopExpression)
	Unop(op: UnaryOperator, rhs: Expression)
	NameRef(name: str)
	VariableRef(variable: Variable)
	FunctionRef(function: FunctionDef, type_arguments: Vector[Type])
	ParameterRef(parameter: ParameterDef)
	LoadSymbol(symbol: Symbol)
	IntLiteral(value: int)
	FloatLiteral(value: float)
	StringLiteral(value: str)
	CharLiteral(value: char)
	BoolLiteral(value: bool)
	StructLiteral(ty: Type, values: List[Expression])
	UnionLiteral(ty: Type, field: str, value: Expression)
	ClassLiteral(typ: Type, arguments: List[LabeledExpression])
	ArrayLiteral(values: List[Expression])
	ArrayLiteral2(size: Expression, ty: Type)
	TypeCast(typ: Type, value: Expression)
	Box(value: Expression)
	Unbox(value: Expression, to_type: Type)
	ToString(value: Expression)
	Typ(ty: Type)
	Variant(ty: Type, variant: EnumVariant)
	EnumLiteral(ty: Type, variant: EnumVariant, values: List[Expression])
	Stmt(statement: Statement)
	If(if_expression: IfExpression)
	Null

pub struct LabeledExpression:
	location: Location
	name: Option[str]
	value: Expression

pub fn struct_literal(ty: Type, values: List[Expression], location: Location) -> Expression:
	Expression(kind: ExpressionKind.StructLiteral(ty, values), ty, location)

pub fn union_literal(ty: Type, field: str, value: Expression, location: Location) -> Expression:
	Expression(kind: ExpressionKind.UnionLiteral(ty, field, value), ty, location)

pub fn array_literal(values: List[Expression], location: Location) -> Expression:
	Expression(kind: ExpressionKind.ArrayLiteral(values), ty: undefined_type(), location)

pub fn array_literal2(size: Expression, ty: Type, location: Location) -> Expression:
	Expression(kind: ExpressionKind.ArrayLiteral2(size, ty), ty: undefined_type(), location)

pub fn parameter_ref(parameter_def: ParameterDef, location: Location) -> Expression:
	let ty = parameter_def.ty
	Expression(kind: ExpressionKind.ParameterRef(parameter_def), ty, location)

pub fn call(callee: Expression, arguments: List[LabeledExpression], ty: Type, location: Location) -> Expression:
	""" Function call expression """
	let c = FunctionCall(callee, arguments)
	let kind = ExpressionKind.Call(c)
	Expression(kind, ty, location)

pub fn get_attr(base: Expression, field: str, ty: Type, location: Location) -> Expression:
	let kind = ExpressionKind.GetAttr(base, field)
	Expression(kind, ty, location)

pub fn box_expression(value: Expression, location: Location) -> Expression:
	let kind = ExpressionKind.Box(value)
	Expression(kind, ty: undefined_type(), location)

pub fn unbox_expression(value: Expression, to_type: Type, location: Location) -> Expression:
	let kind = ExpressionKind.Unbox(value, to_type)
	Expression(kind, ty: undefined_type(), location)

pub struct FunctionCall:
	callee: Expression
	arguments: List[LabeledExpression]

pub fn subscript(base: Expression, indici: List[Expression], ty: Type, location: Location) -> Expression:
	let kind = ExpressionKind.GetIndex(base, indici)
	Expression(kind, ty, location)

pub fn statement_expression(statement: Statement) -> Expression:
	let kind = ExpressionKind.Stmt(statement)
	let ty = statement.ty
	let location = statement.location
	Expression(kind, ty, location)

# fn cast(value: Expression, to_type: Type, location: Location) -> Expression:
#     let kind = ExpressionKind.TypeCast(to_type, value)
#     Expression(kind, ty: to_type, location)

#fn array_index(base: Expression, index: Expression, location: Location) -> Expression:
#    pass

# Reference a variable:
fn variable_ref(variable: Variable, location: Location) -> Expression:
	let kind = ExpressionKind.VariableRef(variable)
	Expression(kind, ty: variable.ty, location)

# Reference a symbol:
pub fn name_ref(name: str, location: Location) -> Expression:
	let kind = ExpressionKind.NameRef(name)
	let ty = undefined_type()
	Expression(kind, ty, location)

pub struct BinopExpression:
	lhs: Expression
	op: BinaryOperator
	rhs: Expression

pub enum BinaryOperator:
	And
	Or
	Less
	LessEquals
	Greater
	GreaterEquals
	Equals
	NotEquals
	BitAnd
	BitXor
	BitOr
	ShiftLeft
	ShiftRight
	Add
	Sub
	Mul
	Div

pub fn is_comparison_op(op: BinaryOperator) -> bool:
	case op:
		Less:
			true
		LessEquals:
			true
		Greater:
			true
		GreaterEquals:
			true
		Equals:
			true
		NotEquals:
			true
	else:
		false

pub fn binop(lhs: Expression, op: BinaryOperator, rhs: Expression, ty: Type, location: Location) -> Expression:
	let b = BinopExpression(lhs, op, rhs)
	let kind = ExpressionKind.Binop(b)
	Expression(kind, ty, location)

pub struct IfExpression:
	condition: Expression
	true_value: Expression
	false_value: Expression

pub enum UnaryOperator:
	Not
	Minus

pub fn unop(op: UnaryOperator, value: Expression, ty: Type, location: Location) -> Expression:
	let kind = ExpressionKind.Unop(op, value)
	Expression(kind, ty, location)

pub fn bool_literal(value: bool, location: Location) -> Expression:
	let kind = ExpressionKind.BoolLiteral(value)
	let ty = bool_type()
	Expression(kind, ty, location)

pub fn integer_literal(value: int, location: Location) -> Expression:
	let kind = ExpressionKind.IntLiteral(value)
	let ty = int_type()
	Expression(kind, ty, location)

pub fn float_literal(value: float, location: Location) -> Expression:
	let kind = ExpressionKind.FloatLiteral(value)
	let ty = float_type()
	Expression(kind, ty, location)

pub fn string_literal(value: str, location: Location) -> Expression:
	let kind = ExpressionKind.StringLiteral(value)
	let ty = str_type()
	Expression(kind, ty, location)

pub fn char_literal(value: char, location: Location) -> Expression:
	let kind = ExpressionKind.CharLiteral(value)
	let ty = char_type()
	Expression(kind, ty, location)

pub fn to_string(value: Expression, location: Location) -> Expression:
	let kind = ExpressionKind.ToString(value)
	Expression(kind, ty: str_type(), location)

pub fn null_value(location: Location) -> Expression:
	Expression(kind: ExpressionKind.Null(), ty: opaque_type(), location)

pub fn print_ast2(module_set: ModuleSet):
	for module in module_set.modules:
		print_ast(module)

pub fn print_ast(module: ModuleDef):
	print("Module: " + module.name)
	let printer = AstPrinter()
	printer.indent()
	for imp in module.imports:
		case imp.kind:
			Self:
				printer.print2(txt: "import {imp.modname}")
			Names(names):
				printer.print2(txt: "from {imp.modname} import ..")
	let visitor = new_print_visitor(printer)
	visit_module(visitor, module)
	printer.dedent()

pub fn new_print_visitor(printer: AstPrinter) -> Visitor[AstPrinter]:
	Visitor:
		data: printer
		on_definition: print_ast_definition
		on_type: print_ast_type
		on_statement: print_ast_statement
		on_expression: print_ast_expression
		on_node: print_ast_node

pub class AstPrinter:
	var indent_level: int = 0

	pub fn indent():
		indent_level += 1

	pub fn dedent():
		indent_level -= 1

	fn get_prefix() -> str:
		str_repeat(text: "   ", count: indent_level)

	pub fn print2(txt: str):
		let prefix = get_prefix()
		print(prefix + txt)

fn print_ast_definition(printer: AstPrinter, definition: Definition, phase: VisitPhase):
	case phase:
		Pre:
			printer.print2(txt: definition_to_str(definition))
			case definition:
				Struct(struct_def):
					for type_parameter in struct_def.type_parameters:
						printer.print2(txt: "- TP {node_id_to_string(type_parameter.id)}")
					for field in struct_def.fields:
						printer.print2(txt: "- FIELD {field.name}")
				Enum(enum_def):
					for type_parameter in enum_def.type_parameters:
						printer.print2(txt: "- TP {node_id_to_string(type_parameter.id)}")
				Class(class_def):
					for type_parameter in class_def.type_parameters:
						printer.print2(txt: "- TP {node_id_to_string(type_parameter.id)}")
			else:
				pass
			printer.indent()
		Post:
			printer.dedent()
	else:
		pass

fn print_ast_type(printer: AstPrinter, ty: Type, phase: VisitPhase):
	case phase:
		Pre:
			let txt = type_to_string(ty)
			printer.print2(txt: "TYPE {txt}")
			printer.indent()
		Post:
			printer.dedent()
	else:
		pass

fn statement_to_string(statement: Statement) -> str:
	case statement.kind:
		Expr(x):
			"EXPR"
		Assignment(target, op, expr):
			case op:
				Some(op):
					let op_txt = binary_op_to_str(op)
					"ASSIGN({op_txt})"
				None:
					"ASSIGN"
		If(x):
			"IF"
		Return(x):
			"RETURN"
		Raise(x):
			"RAISE"
		Compound(x):
			"COMPOUND"
		Pass:
			"PASS"
		Break:
			"BREAK"
		Continue:
			"CONTINUE"
		Loop(loopy):
			"LOOP"
		While(whilly):
			"WHILE"
		For(f):
			"FOR"
		Try(t):
			"TRY"
		Case(f):
			"CASE"
		Let(letty):
			"LET {node_id_to_string(letty.variable.id)}"
		Switch(switchy):
			"SWITCH"
		Unreachable:
			"UNREACHABLE"

fn print_ast_statement(printer: AstPrinter, statement: Statement, phase: VisitPhase):
	case phase:
		Pre:
			printer.print2(txt: "STMT {statement}")
			printer.indent()
		Post:
			printer.dedent()
	else:
		pass

fn expression_to_string(expression?: Expression) -> str:
	case expression.kind:
		StringLiteral(value):
			"String={value}"
		CharLiteral(value):
			"Char={value}"
		IntLiteral(value):
			"Integer={value}"
		FloatLiteral(val):
			"Float={float_to_str(val)}"
		BoolLiteral(val):
			if val:
				"Bool(true)"
			else:
				"Bool(false)"
		Call(c):
			"CALL"
		NameRef(name):
			"REF({name})"
		LoadSymbol(symbol):
			"LOAD_SYM({symbol})"
		GetAttr(base, attr):
			"GET-ATTR({attr})"
		GetIndex(base, indici):
			"GET-INDEX"
		Null:
			"NULL"
		Binop(op):
			let op_txt = binary_op_to_str(op: op.op)
			"BINOP({op_txt})"
		Unop(op, value):
			let op_txt = unary_op_to_str(op)
			"UNOP({op_txt})"
		VariableRef(v):
			"VARIABLE-REF({node_id_to_string(v.id)})"
		FunctionRef(function, type_arguments):
			let txt = "FN-{function.name}"
			if type_arguments.is_empty():
				txt
			else:
				txt + types_to_string(typs: type_arguments)
		ParameterRef(parameter_def):
			"parameter:{node_id_to_string(parameter_def.id)}"
		StructLiteral(ty, values):
			"STRUCT-LITERAL"
		UnionLiteral(ty, field, value):
			"UNION-LITERAL field={field}"
		ClassLiteral(ty, arguments):
			"CLASS-LITERAL"
		ArrayLiteral(values):
			"ARRAY-LITERAL"
		ArrayLiteral2(size, ty):
			"ARRAY-LITERAL2"
		TypeCast(ty, value):
			"TYPE-CAST"
		Box(value):
			"BOX"
		Unbox(value, to_type):
			"UNBOX"
		ToString(value):
			"TOSTRING"
		Typ(ty):
			"TYPE"
		Variant(ty, v):
			"VARIANT"
		EnumLiteral(ty, v, values):
			"ENUM-LITERAL"
		Stmt(statement):
			let txt = statement_to_string(statement)
			"STMT-{txt}"
		If(if_expression):
			"IF-EXPR"

fn print_ast_expression(printer: AstPrinter, expression: Expression, phase: VisitPhase):
	case phase:
		Pre:
			let ty_txt = type_to_string(expression.ty)
			printer.print2(txt: "EXPR {expression} ---> {ty_txt}")
			printer.indent()
		Post:
			printer.dedent()
	else:
		pass

fn print_ast_node(printer: AstPrinter, node: VisitNode, phase: VisitPhase):
	pass

pub fn binary_op_to_str(op?: BinaryOperator) -> str:
	case op:
		And:
			"and"
		Or:
			"or"
		Greater:
			">"
		GreaterEquals:
			">="
		Less:
			"<"
		LessEquals:
			"<="
		Equals:
			"=="
		NotEquals:
			"!="
		BitAnd:
			"bitand"
		BitXor:
			"bitxor"
		BitOr:
			"bitor"
		ShiftLeft:
			"shl"
		ShiftRight:
			"shr"
		Add:
			"+"
		Sub:
			"-"
		Mul:
			"*"
		Div:
			"/"

fn unary_op_to_str(op: UnaryOperator) -> str:
	case op:
		Not:
			"not"
		Minus:
			"-"

pub struct Visitor[D]:
	data: D
	on_definition: fn(D, Definition, VisitPhase)
	on_type: fn(D, Type, VisitPhase)
	on_statement: fn(D, Statement, VisitPhase)
	on_expression: fn(D, Expression, VisitPhase)
	on_node: fn(D, VisitNode, VisitPhase)

pub enum VisitPhase:
	Pre
	Mid
	Post

pub enum VisitNode:
	Arm(arm: CaseArm)
	ScopeNode(scope: Scope)
	ModuleNode(module: ModuleDef)

pub fn visit_module_set[T](visitor: Visitor[T], module_set: ModuleSet):
	for module in module_set.modules:
		let module_node = VisitNode.ModuleNode(module)
		visitor.on_node(data: visitor.data, module_node, phase: VisitPhase.Pre())
		visit_module(visitor, module)
		visitor.on_node(data: visitor.data, module_node, phase: VisitPhase.Post())

pub fn visit_module[T](visitor: Visitor[T], module: ModuleDef):
	for definition in module.definitions:
		visit_definition(visitor, definition)


fn visit_definition[T](visitor: Visitor[T], definition: Definition):
	visitor.on_definition(a: visitor.data, definition, phase: VisitPhase.Pre())
	case definition:
		Module(module):
			visit_module(visitor, module)
		Macro(macro_def):
			pass
		Function(function_def):
			# print("VISIT {func.name}")
			for parameter in function_def.parameters:
				visit_type(visitor, ty: parameter.ty)
			case function_def.this_parameter:
				Some(p):
					visit_type(visitor, ty: p.ty)
				None:
					pass
			visit_type(visitor, ty: function_def.info.return_type)
			visit_type(visitor, ty: function_def.info.except_type)
			case function_def.body:
				Intern(scoped_block):
					visit_statement(visitor, statement: scoped_block.body)
				Extern(libname):
					pass
				None:
					pass
		Enum(enum_def):
			for variant in enum_def.variants:
				for p in variant.payload:
					visit_type(visitor, ty: p)

		Struct(struct_def):
			for field in struct_def.fields:
				visit_type(visitor, ty: field.ty)
		Class(class_def):
			for d2 in class_def.definitions:
				visit_definition(visitor, definition: d2)
		Interface(interface_def):
			for d2 in interface_def.definitions:
				visit_definition(visitor, definition: d2)
		Impl(impl_def):
			visit_type(visitor, ty: impl_def.interface_type)
			visit_type(visitor, ty: impl_def.target_type)
			for d2 in impl_def.definitions:
				visit_definition(visitor, definition: d2)
		Var(variable_def):
			visit_type(visitor, ty: variable_def.variable.ty)
			case variable_def.value:
				Intern(value):
					case value:
						Some(v2):
							visit_expression(visitor, expression: v2)
						None:
							pass
				Extern(libname, initialized):
					pass
		Type(type_def):
			visit_type(visitor, ty: type_def.ty)

	visitor.on_definition(data: visitor.data, definition, phase: VisitPhase.Post())

fn visit_type[T](visitor: Visitor[T], ty: Type):
	# print("Visit type")
	visitor.on_type(data: visitor.data, ty, phase: VisitPhase.Pre())
	case ty.kind:
		App(tycon, type_arguments):
			for type_argument in type_arguments:
				visit_type(visitor, ty: type_argument)
		Function(parameter_types, info):
			for parameter_type in parameter_types:
				visit_type(visitor, ty: parameter_type.ty)
			visit_type(visitor, ty: info.return_type)
			visit_type(visitor, ty: info.except_type)
		TypeVar(type_variable):
			case type_variable.ty:
				Some(ty2):
					visit_type(visitor, ty: ty2)
				None:
					pass
		Array(element_type, size):
			visit_type(visitor, ty: element_type)
		Pointer(pointed_type):
			visit_type(visitor, ty: pointed_type)
	else:
		pass
	visitor.on_type(data: visitor.data, ty, phase: VisitPhase.Post())

pub fn visit_statement[T](visitor: Visitor[T], statement: Statement):
	visitor.on_statement(data: visitor.data, statement, phase: VisitPhase.Pre())
	case statement.kind:
		Let(let_statement):
			case let_statement.type_hint:
				Some(ty):
					visit_type(visitor, ty)
				None:
					pass
			visit_expression(visitor, expression: let_statement.value)
		If(if_statement):
			visit_expression(visitor, expression: if_statement.condition)
			var arm_node = VisitNode.ScopeNode(if_statement.true_block.scope)
			visitor.on_node(data: visitor.data, arm_node, phase: VisitPhase.Pre())
			visit_statement(visitor, statement: if_statement.true_block.body)
			visitor.on_node(data: visitor.data, arm_node, phase: VisitPhase.Post())
			arm_node = VisitNode.ScopeNode(if_statement.false_block.scope)
			visitor.on_node(data: visitor.data, arm_node, phase: VisitPhase.Pre())
			visit_statement(visitor, statement: if_statement.false_block.body)
			visitor.on_node(data: visitor.data, arm_node, phase: VisitPhase.Post())
		While(while_statement):
			visit_expression(visitor, expression: while_statement.condition)
			visit_statement(visitor, statement: while_statement.block.body)
		Loop(loop_statement):
			visit_statement(visitor, statement: loop_statement.block.body)
		Switch(switch_statement):
			visit_expression(visitor, expression: switch_statement.value)
			for arm in switch_statement.arms:
				visit_expression(visitor, expression: arm.value)
				visit_statement(visitor, statement: arm.block.body)
			visit_statement(visitor, statement: switch_statement.default_block.body)
		For(for_statement):
			visit_expression(visitor, expression: for_statement.iter_value)
			visitor.on_statement(data: visitor.data, statement, phase: VisitPhase.Mid())
			visit_statement(visitor, statement: for_statement.block.body)
		Try(try_statement):
			visit_statement(visitor, statement: try_statement.try_block.body)
			visit_type(visitor, ty: try_statement.except_type)
			visitor.on_statement(data: visitor.data, statement, phase: VisitPhase.Mid())
			visit_statement(visitor, statement: try_statement.except_block.body)
		Case(case_statement):
			visit_expression(visitor, expression: case_statement.value)
			visitor.on_statement(data: visitor.data, statement, phase: VisitPhase.Mid())
			for arm in case_statement.arms:
				let arm_node = VisitNode.Arm(arm)
				visitor.on_node(data: visitor.data, arm_node, phase: VisitPhase.Pre())
				visit_statement(visitor, statement: arm.block.body)
				visitor.on_node(data: visitor.data, arm_node, phase: VisitPhase.Post())
			case case_statement.else_block:
				Some(else_block):
					visit_statement(visitor, statement: else_block.body)
				None:
					pass
		Compound(inner):
			for s in inner:
				visit_statement(visitor, statement: s)
		Expr(expression):
			visit_expression(visitor, expression)
		Assignment(target, op, expr):
			visit_expression(visitor, expression: target)
			visit_expression(visitor, expression: expr)
		Return(opt_val):
			case opt_val:
				Some(expr):
					visit_expression(visitor, expression: expr)
				None:
					pass
		Raise(exc_val):
			visit_expression(visitor, expression: exc_val)
	else:
		pass
	visitor.on_statement(data: visitor.data, statement, phase: VisitPhase.Post())

pub fn visit_expression[T](visitor: Visitor[T], expression: Expression):
	visitor.on_expression(data: visitor.data, expression, phase: VisitPhase.Pre())

	case expression.kind:
		Call(v):
			visit_expression(visitor, expression: v.callee)
			for arg in v.arguments:
				visit_expression(visitor, expression: arg.value)
		GetAttr(base, index):
			visit_expression(visitor, expression: base)
		GetIndex(base, indici):
			visit_expression(visitor, expression: base)
			for index in indici:
				visit_expression(visitor, expression: index)
		Binop(v):
			visit_expression(visitor, expression: v.lhs)
			visit_expression(visitor, expression: v.rhs)
		Unop(op,value):
			visit_expression(visitor, expression: value)
		FunctionRef(function_def, type_arguments):
			for type_argument in type_arguments:
				visit_type(visitor, ty: type_argument)
		StructLiteral(ty, values):
			visit_type(visitor, ty)
			for value in values:
				visit_expression(visitor, expression: value)
		UnionLiteral(ty, field, value):
			visit_type(visitor, ty)
			visit_expression(visitor, expression: value)
		ArrayLiteral(values):
			for value in values:
				visit_expression(visitor, expression: value)
		ArrayLiteral2(size, ty):
			visit_expression(visitor, expression: size)
			visit_type(visitor, ty)
		ClassLiteral(ty, arguments):
			visit_type(visitor, ty)
			for arg in arguments:
				visit_expression(visitor, expression: arg.value)
		TypeCast(ty, value):
			visit_type(visitor, ty)
			visit_expression(visitor, expression: value)
		Box(value):
			visit_expression(visitor, expression: value)
		Unbox(value, to_type):
			visit_type(visitor, ty: to_type)
			visit_expression(visitor, expression: value)
		ToString(value):
			visit_expression(visitor, expression: value)
		Typ(ty):
			visit_type(visitor, ty)
		EnumLiteral(ty, v, values):
			for value in values:
				visit_expression(visitor, expression: value)
		Stmt(statement):
			visit_statement(visitor, statement)
		If(if_expression):
			visit_expression(visitor, expression: if_expression.true_value)
			visit_expression(visitor, expression: if_expression.condition)
			visit_expression(visitor, expression: if_expression.false_value)
	else:
		pass

	visitor.on_expression(data: visitor.data, expression, phase: VisitPhase.Post())
