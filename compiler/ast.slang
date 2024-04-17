
from std import print, float_to_str
from strlib import str_repeat, str_join
from utils import panic, assert, log_info, log_error
from location import Location, location_default
from datatypes import List, Option, option_unwrap, option_is_some
from dicttype import Dictionary

# Name coupled with global unique ID:
struct NodeId:
    name: str
    id: int

fn node_id_equal(node_id1: NodeId, node_id2: NodeId) -> bool:
    if node_id1.id == node_id2.id:
        return true
    else:
        return false

fn node_id_to_string(id?: NodeId) -> str:
    return "{id.name}${id.id}"

# TODO: implement type-defs!
struct Type:
    kind: TypeKind
    was_generic: bool

fn clone_type(ty?: Type) -> Type:
    let ty2 = new_type(kind: ty.kind)
    ty2.was_generic = ty.was_generic
    return ty2

fn new_type(kind: TypeKind) -> Type:
    return Type(kind, was_generic: false)

fn types_to_string(typs: List[Type]) -> str:
    let parts: List[str] = List()
    for ty in typs:
        parts.append(type_to_string(ty))
    let txt = "[" + str_join(parts, sep: ", ") + "]"
    return txt

fn type_to_string(ty?: Type) -> str:
    let txt = "?"
    case ty.kind:
        Base(base):
            case base:
                Str:
                    txt = "STR"
                Char:
                    txt = "CHAR"
                Int:
                    txt = "INT"
                Bool:
                    txt = "BOOL"
                Float:
                    txt = "FLOAT"
        Opaque:
            txt = "OPAQUE"
        Void:
            txt = "VOID"
        TypeExpression(expr):
            txt = "TYPE-EXPR"
        Array(element_type, size):
            txt = "ARRAY({type_to_string(element_type)} x {size})"
        Function(parameter_types, info):
            let typs = get_types_from_parameter_types(parameter_types)
            txt = "FUNC-TYPE({types_to_string(typs)},{type_to_string(info.return_type)},{type_to_string(info.except_type)})"
        Undefined:
            txt = "UNDEFINED"
        TypeParam(param):
            txt = "TYPE-PARAM({node_id_to_string(param.id)})"
        TypeVar(v):
            case v.ty:
                None:
                    txt = "TYPE-VAR(id={v.unique})"
                Some(ty_assigned):
                    txt = "TYPE-VAR(id={v.unique},{type_to_string(ty_assigned)})"
        App(tycon, type_arguments):
            if type_arguments.is_empty():
                txt = tycon_to_str(tycon)
            else:
                let args = types_to_string(typs: type_arguments)
                txt = tycon_to_str(tycon) + args
        
    if ty.was_generic:
        txt = "@" + txt

    return txt

fn change_type_to(ty: Type, ty2: Type):
    # Adjust ty to ty2
    ty.kind = ty2.kind
    # TBD: copy was generic?
    # ty.was_generic = ty.was_generic

fn apply_tycon(tycon: TyCon, type_arguments: List[Type]) -> Type:
    # if type_arguments
    let type_parameters = tycon_get_type_parameters(tycon)
    # Check lengths!
    assert(condition: type_parameters.len() == type_arguments.len(), message: "type arguments does not match amount of type parameters")
    return new_type(kind: TypeKind.App(tycon, type_arguments))

fn subst(ty: Type, m: Dictionary[Type]) -> Type:
    case ty.kind:
        TypeParam(p):
            case m.maybe_get(key: p.id.name):
                Some(ty3):
                    # Idea is to record if we once were a type-parameter:
                    let ty4 = clone_type(ty3)
                    ty4.was_generic = true
                    return ty4
                None:
                    return ty
        Function(parameter_types, info):
            let parameter_types2: List[ParameterType] = List()
            for p in parameter_types:
                parameter_types2.append(ParameterType(label: p.label, ty: subst(ty: p.ty, m)))
            let info2 = FunctionInfo:
                no_return: info.no_return
                return_type: subst(ty: info.return_type, m)
                except_type: subst(ty: info.except_type, m)
            return function_type(parameter_types: parameter_types2, info: info2)
        Array(element_type, size):
            element_type = subst(ty: element_type, m)
            return array_type(element_type, size)
        App(tycon, type_arguments):
            return apply_tycon(tycon, type_arguments: subst_many(typs: type_arguments, m))
    else:
        return ty

fn subst_many(typs: List[Type], m: Dictionary[Type]) -> List[Type]:
    let typs2: List[Type] = List()
    for ty in typs:
        typs2.append(subst(ty, m))
    return typs2

fn create_subst_mapping(type_parameters: List[TypeParameter], type_arguments: List[Type]) -> Dictionary[Type]:
    if type_parameters.len() != type_arguments.len():
        for type_parameter in type_parameters:
            log_error("type parameter: {node_id_to_string(type_parameter.id)}")
        for type_argument in type_arguments:
            log_error("type argument: {type_to_string(type_argument)}")
        panic("amount of type parameters and type arguments must be equal")
    let m: Dictionary[Type] = Dictionary()
    let tpi = type_parameters.iter()
    for ty in type_arguments:
        let tp = option_unwrap(tpi.next())
        m.insert(key: tp.id.name, value: ty)
    return m


fn is_enum_type(ty?: Type) -> bool:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Enum(x):
                    return true
            else:
                return false
    else:
        return false

fn is_class_type(ty?: Type) -> bool:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Class(x):
                    return true
            else:
                return false
    else:
        return false

fn is_void_type(ty?: Type) -> bool:
    case ty.kind:
        Void:
            return true
    else:
        return false

fn is_int_type(ty?: Type) -> bool:
    case ty.kind:
        Base(base):
            case base:
                Int:
                    return true
            else:
                return false
    else:
        return false

fn is_str_type(ty?: Type) -> bool:
    case ty.kind:
        Base(base):
            case base:
                Str:
                    return true
            else:
                return false
    else:
        return false

fn is_char_type(ty?: Type) -> bool:
    case ty.kind:
        Base(base):
            case base:
                Char:
                    return true
            else:
                return false
    else:
        return false

fn is_bool_type(ty?: Type) -> bool:
    case ty.kind:
        Base(base):
            case base:
                Bool:
                    return true
            else:
                return false
    else:
        return false

fn is_float_type(ty?: Type) -> bool:
    case ty.kind:
        Base(base):
            case base:
                Float:
                    return true
            else:
                return false
    else:
        return false

fn is_array_type(ty?: Type) -> bool:
    case ty.kind:
        Array(element_type, size):
            return true
    else:
        return false

fn is_opaque_type(ty?: Type) -> bool:
    case ty.kind:
        Opaque:
            return true
    else:
        return false

fn get_element_type_from_type(ty?: Type) -> Type:
    case ty.kind:
        Array(element_type, size):
            return element_type
    else:
        panic("No array type")

fn get_array_size_from_type(ty?: Type) -> int:
    case ty.kind:
        Array(element_type, size):
            return size
    else:
        panic("No array type")

fn is_tycon_app_type(ty?: Type) -> bool:
    case ty.kind:
        App(tycon, args):
            return true
    else:
        return false

fn is_type_parameter_type(ty?: Type) -> bool:
    case ty.kind:
        TypeParam(p):
            return true
    else:
        return false

fn is_type_var_type(ty?: Type) -> bool:
    case ty.kind:
        TypeVar(v):
            return true
    else:
        return false

fn get_type_var_from_type(ty?: Type) -> TypeVariable:
    case ty.kind:
        TypeVar(v):
            return v
    else:
        panic("Type must be type variable reference")

fn deref_type_var(ty?: Type) -> Type:
    case ty.kind:
        TypeVar(type_var):
            case type_var.ty:
                None:
                    panic("Must be assigned type!")
                Some(t):
                    t = clone_type(t)
                    t.was_generic = ty.was_generic
                    return t
    else:
        return ty


fn get_type_parameter_from_type(ty?: Type) -> TypeParameter:
    case ty.kind:
        TypeParam(p):
            return p
    else:
        panic("Type must be type parameter")

fn is_function_type(ty?: Type) -> bool:
    case ty.kind:
        Function(p, i):
            return true
    else:
        return false

fn get_parameter_types_from_type(ty?: Type) -> List[ParameterType]:
    case ty.kind:
        Function(p, i):
            return p
    else:
        panic("Type must be function type")

fn get_types_from_parameter_types(p2?: List[ParameterType]) -> List[Type]:
    let t: List[Type] = List()
    for p in p2:
        t.append(p.ty)
    return t

fn get_return_type_from_type(ty?: Type) -> Type:
    case ty.kind:
        Function(p, i):
            return i.return_type
    else:
        panic("Type must be function type")

fn get_except_type_from_type(ty?: Type) -> Type:
    case ty.kind:
        Function(p, i):
            return i.except_type
    else:
        panic("Type must be function type")

fn get_enum_variant_from_type(ty: Type, attr: str) -> Option[EnumVariant]:
    let enum_def = get_enum_def_from_type(ty)
    return get_enum_variant(enum_def, attr)

fn get_enum_variant(enum_def: EnumDef, attr: str) -> Option[EnumVariant]:
    case enum_def.scope.lookup(name: attr):
        Some(symbol):
            case symbol:
                Variant(v):
                    return Option.Some(v)
            else:
                # panic("get_enum_variant: symbol must be ")
                return Option.None()
        None:
            return Option.None()

fn get_enum_variant_names_from_type(ty?: Type) -> List[str]:
    let enum_def = get_enum_def_from_type(ty)
    let names: List[str] = List()
    for variant in enum_def.variants:
        names.append(variant.name)
    return names

fn get_enum_def_from_type(ty?: Type) -> EnumDef:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Enum(enum_def):
                    return enum_def
            else:
                panic("get_enum_def_from_type: type must be enum")
    else:
        panic("get_enum_def_from_type: type must be enum")

fn get_subst_map(ty: Type) -> Dictionary[Type]:
    case ty.kind:
        App(tycon, type_arguments):
            return create_subst_mapping(type_parameters: tycon_get_type_parameters(tycon), type_arguments)
    else:
        panic("Must be App type")

fn get_variant_payload_types(ty: Type, variant: EnumVariant) -> List[Type]:
    let m = get_subst_map(ty)
    let payload = subst_many(typs: variant.payload, m)
    return payload

fn get_field_types(ty: Type) -> List[Type]:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Struct(struct_def):
                    let m = create_subst_mapping(type_parameters: struct_def.type_parameters, type_arguments)
                    let field_types: List[Type] = List()
                    for field in struct_def.fields:
                        field_types.append(subst(ty: field.ty, m))
                    return field_types
            else:
                panic("Type without fields")
    else:
        panic("Type without fields")

fn is_struct_type(ty?: Type) -> bool:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Struct(struct_def):
                    return true
            else:
                return false
    else:
        return false

fn get_struct_def_from_type(ty?: Type) -> StructDef:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Struct(struct_def):
                    return struct_def
            else:
                panic("No struct type")
    else:
        panic("No struct type")

fn get_struct_name_from_type(ty: Type) -> str:
    let struct_def = get_struct_def_from_type(ty)
    return struct_def.id.name

fn has_field(ty: Type, attr: str) -> bool:
    return option_is_some(get_field_type(ty, attr))

fn get_field_type(ty: Type, attr: str) -> Option[Type]:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Struct(struct_def):
                    case struct_def.scope.lookup(name: attr):
                        Some(sym):
                            let m = create_subst_mapping(type_parameters: struct_def.type_parameters, type_arguments)
                            case sym:
                                Field(f):
                                    return Option.Some(subst(ty: f.ty, m))
                            else:
                                panic("Struct field must be ")
                        None:
                            return Option.None()
                Class(class_def):
                    case class_def.scope.lookup(name: attr):
                        Some(sym):
                            let m = create_subst_mapping(type_parameters: class_def.type_parameters, type_arguments)
                            case sym:
                                Function(function_def):
                                    return Option.Some(subst(ty: get_function_type(function_def), m))
                                Var(v):
                                    return Option.Some(subst(ty: v.ty, m))
                            else:
                                panic("class must contain func/vars")
                        None:
                            return Option.None()
            else:
                return Option.None()
    else:
        return Option.None()

fn get_struct_field_index(ty: Type, attr: str) -> int:
    let struct_def = get_struct_def_from_type(ty)
    let index = 0
    for field in struct_def.fields:
        if field.name == attr:
            return index
        index += 1
    panic("No attr: {attr}")

fn get_method_from_type(ty: Type, attr: str) -> FunctionDef:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Class(c):
                    let sym = option_unwrap(c.scope.lookup(name: attr))
                    case sym:
                        Function(function_def):
                            return function_def
                    else:
                        panic("class must contain func/vars")
            else:
                panic("No class: {type_to_string(ty)}")
    else:
        panic("No class: {type_to_string(ty)}")

fn get_class_def_from_type(ty: Type) -> ClassDef:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Class(class_def):
                    return class_def
            else:
                panic("No class type")
    else:
        panic("No class type")

fn get_tycon_from_type(ty?: Type) -> TyCon:
    case ty.kind:
        App(tycon, args):
            return tycon
    else:
        panic("Must be App type")

fn get_type_arguments_from_type(ty?: Type) -> List[Type]:
    case ty.kind:
        App(tycon, args):
            return args
    else:
        panic("Must be App type")

enum TypeKind:
    Base(base: BaseType)
    Undefined
    Opaque
    Void
    TypeExpression(expression: Expression)
    Function(parameter_types: List[ParameterType], info: FunctionInfo)
    TypeParam(type_parameter: TypeParameter)
    TypeVar(type_variable: TypeVariable)
    Array(element_type: Type, size: int)
    
    # Application of a type-constructor:
    App(tycon: TyCon, type_arguments: List[Type])

struct ParameterType:
    label: Option[str]
    ty: Type

enum BaseType:
    Bool
    Int
    Str
    Char
    Float

struct TypeVariable:
    unique: int
    ty: Option[Type]  # assigned type

enum TyCon:
    Struct(struct_def: StructDef)
    Enum(enum_def: EnumDef)
    Class(class_def: ClassDef)

fn tycon_to_str(tycon: TyCon) -> str:
    case tycon:
        Struct(struct_def):
            return "struct({node_id_to_string(struct_def.id)})"
        Enum(enum_def):
            return "enum({node_id_to_string(enum_def.id)})"
        Class(class_def):
            return "class({node_id_to_string(class_def.id)})"

fn tycon_equal(tycon1: TyCon, tycon2: TyCon) -> bool:
    case tycon1:
        Struct(struct_def1):
            case tycon2:
                Struct(struct_def2):
                    return node_id_equal(node_id1: struct_def1.id, node_id2: struct_def2.id)
            else:
                return false
        Enum(enum_def1):
            case tycon2:
                Enum(enum_def2):
                    return node_id_equal(node_id1: enum_def1.id, node_id2: enum_def2.id)
            else:
                return false
        Class(class_def1):
            case tycon2:
                Class(class_def2):
                    return node_id_equal(node_id1: class_def1.id, node_id2: class_def2.id)
            else:
                return false

fn tycon_get_type_parameters(tycon: TyCon) -> List[TypeParameter]:
    case tycon:
        Struct(struct_def):
            return struct_def.type_parameters
        Enum(enum_def):
            return enum_def.type_parameters
        Class(class_def):
            return class_def.type_parameters

fn void_type() -> Type:
    return new_type(kind: TypeKind.Void())

fn new_base_type(base: BaseType) -> Type:
    return new_type(kind: TypeKind.Base(base))

fn bool_type() -> Type:
    return new_base_type(base: BaseType.Bool())

fn int_type() -> Type:
    return new_base_type(base: BaseType.Int())

fn float_type() -> Type:
    return new_base_type(base: BaseType.Float())

fn str_type() -> Type:
    return new_base_type(base: BaseType.Str())

fn char_type() -> Type:
    return new_base_type(base: BaseType.Char())

# Opaque type, void*
fn opaque_type() -> Type:
    return new_type(kind: TypeKind.Opaque())

fn undefined_type() -> Type:
    return new_type(kind: TypeKind.Undefined())

fn array_type(element_type: Type, size: int) -> Type:
    return new_type(kind: TypeKind.Array(element_type, size))

fn type_expression(expr: Expression) -> Type:
    return new_type(kind: TypeKind.TypeExpression(expr))


fn function_type(parameter_types: List[ParameterType], info: FunctionInfo) -> Type:
    return new_type(kind: TypeKind.Function(parameter_types, info))

fn type_parameter_ref(type_parameter: TypeParameter) -> Type:
    return new_type(kind: TypeKind.TypeParam(type_parameter))

fn new_type_var_ref(type_var: TypeVariable) -> Type:
    return new_type(kind: TypeKind.TypeVar(type_var))

fn new_type_var(unique: int) -> TypeVariable:
    return TypeVariable(unique, ty: Option.None())

fn type_var_equals(type_var1: TypeVariable, type_var2: TypeVariable) -> bool:
    return type_var1.unique == type_var2.unique

struct ModuleSet:
    modules: List[Module]

struct Module:
    name: str
    filename: Option[str]
    imports: List[Import]
    definitions: List[Definition]
    scope: Scope

fn new_module(name: str, filename: Option[str], imports: List[Import], definitions: List[Definition]) -> Module:
    let m = Module:
        name
        filename
        imports
        definitions
        scope: Scope()
    return m

fn module_define_symbol(module: Module, name: str, definition: Definition):
    module.definitions.append(definition)
    # case definition:
    #     Var(variable):
    #         module.scope.define(name, symbol: Symbol.Var(variable: variable.variable))
    #     Function(function):
    #         module.scope.define(name, symbol: Symbol.Function(function))
    #     ExternFunction(external_function):
    #         module.scope.define(name, symbol: Symbol.ExternFunction(external_function))
    #     Enum(enum_def):
    #         module.scope.define(name, symbol: Symbol.TypeConstructor(tycon: TyCon.Enum(enum_def)))
    #     Struct(struct_def):
    #         module.scope.define(name, symbol: Symbol.TypeConstructor(tycon: TyCon.Struct(struct_def)))
    #     Class(class_def):
    #         module.scope.define(name, symbol: Symbol.TypeConstructor(tycon: TyCon.Class(class_def)))

fn import_self(modname: str, location: Location) -> Import:
    let i = Import:
        modname: modname
        location: location
        kind: ImportKind.Self()
    return i

fn import_names(modname: str, location: Location, names: List[str]) -> Import:
    let i = Import:
        modname: modname
        location: location
        kind: ImportKind.Names(names)
    return i

struct Import:
    modname: str
    location: Location
    kind: ImportKind

enum ImportKind:
    Self
    Names(names: List[str])

struct ExternFunctionDef:
    modname: str
    name: str
    parameter_types: List[ParameterType]
    return_type: Type
    no_return: bool
    location: Location

fn extern_function_def(modname: str, name: str, parameter_types: List[ParameterType], return_type: Type, location: Location) -> ExternFunctionDef:
    return ExternFunctionDef(modname, name, parameter_types, return_type, no_return: false, location)

fn extern_function_type(extern_function_def: ExternFunctionDef) -> Type:
    let info = FunctionInfo:
        no_return: extern_function_def.no_return
        return_type: extern_function_def.return_type
        except_type: void_type()
    return function_type(parameter_types: extern_function_def.parameter_types, info)

class Scope:
    var symbols: Dictionary[Symbol] = Dictionary()
    var class_scope: bool = false

    fn define(name: str, symbol: Symbol):
        symbols.insert(key: name, value: symbol)
    
    fn is_defined(name: str) -> bool:
        # Check if given name is defined.
        return option_is_some(lookup(name))

    fn lookup(name: str) -> Option[Symbol]:
        return symbols.maybe_get(key: name)
    
    fn dump():
        log_info("Scope:")
        for name in symbols:
            log_info(" - {name}")

enum Symbol:
    Mod(module: Module)
    Function(function_def: FunctionDef)
    ExternFunction(extern_function_def: ExternFunctionDef)
    Parameter(parameter_def: ParameterDef)
    Var(variable: Variable)
    TypeConstructor(tycon: TyCon)
    Typ(typ: Type)
    Variant(enum_variant: EnumVariant)
    Field(struct_field: StructField)

fn symbol_to_str(symbol: Symbol) -> str:
    case symbol:
        Mod(m):
            return "mod:{m.name}"
        Function(f):
            return "function:{node_id_to_string(f.id)}"
        ExternFunction(f):
            return "extern-function:{f.name}"
        Parameter(p):
            return "parameter:{node_id_to_string(p.id)}"
        Var(v):
            return "var:{node_id_to_string(v.id)}"
        TypeConstructor(v):
            return "tycon"
        Typ(t):
            return "typ"
        Variant(v):
            return "EnumVariant({v.name})"
        Field(f):
            return "Field({f.name})"

enum Definition:
    Function(function_def: FunctionDef)
    ExternFunction(extern_function_def: ExternFunctionDef)
    Enum(enum_def: EnumDef)
    Struct(struct_def: StructDef)
    Class(class_def: ClassDef)
    Var(var_def: VariableDef)

struct VariableDef:
    variable: Variable
    value: Option[Expression]
    
fn new_type_parameter(name: str, id: int, location: Location) -> TypeParameter:
    return TypeParameter(id: NodeId(name, id), location)

fn type_parameter_equals(tp1: TypeParameter, tp2: TypeParameter) -> bool:
    return node_id_equal(node_id1: tp1.id, node_id2: tp2.id)

struct TypeParameter:
    id: NodeId
    location: Location

fn struct_def(name: str, id: int, type_parameters: List[TypeParameter], fields: List[StructField], location: Location) -> StructDef:
    let s = StructDef:
        id: NodeId(name, id)
        is_union: false
        type_parameters: type_parameters
        fields: fields
        location: location
        scope: Scope()
    return s

struct StructDef:
    id: NodeId
    is_union: bool
    type_parameters: List[TypeParameter]
    fields: List[StructField]
    location: Location
    scope: Scope

class StructBuilder:
    var nodeId: NodeId = NodeId(name: "", id: 0)
    var is_union: bool = false
    var location: Location = location_default()
    var type_parameters: List[TypeParameter] = List()
    var fields: List[StructField] = List()

    fn set_name(name: str):
        nodeId.name = name
    
    fn set_id(id?: int):
        nodeId.id = id
    
    fn set_is_union(is_union?: bool):
        this.is_union = is_union

    fn add_type_parameter(name: str, id: int, location: Location) -> Type:
        let type_parameter = new_type_parameter(name, id, location)
        type_parameters.append(type_parameter)
        return type_parameter_ref(type_parameter)

    fn add_field(name: str, ty: Type, location: Location):
        fields.append(StructField(name, ty, location))

    fn finish() -> StructDef:
        let scope = Scope()
        for field in fields:
            scope.define(name: field.name, symbol: Symbol.Field(field))
        let struct_def = StructDef:
            id: nodeId
            is_union: is_union
            type_parameters: type_parameters
            fields: fields
            location: location
            scope
        return struct_def

struct StructField:
    name: str
    ty: Type
    location: Location

fn enum_def(name: str, id: int, location: Location, type_parameters: List[TypeParameter], variants: List[EnumVariant]) -> EnumDef:
    let e = EnumDef:
        id: NodeId(name, id)
        location: location
        type_parameters: type_parameters
        variants: variants
        scope: Scope()
    return e

struct EnumDef:
    id: NodeId
    location: Location
    type_parameters: List[TypeParameter]
    variants: List[EnumVariant]
    scope: Scope

struct EnumVariant:
    name: str
    tag_value: int
    location: Location
    payload: List[Type]

struct ClassDef:
    id: NodeId
    location: Location
    type_parameters: List[TypeParameter]
    definitions: List[Definition]
    scope: Scope

fn function_def(name: str, id: int, type_parameters: List[TypeParameter], this_parameter: Option[ParameterDef], parameters: List[ParameterDef], return_type: Type, except_type: Type, body: Statement, location: Location) -> FunctionDef:
    let info = FunctionInfo:
        no_return: false
        return_type
        except_type

    let f = FunctionDef:
        id: NodeId(name, id)
        is_pub: true
        info
        type_parameters
        this_parameter
        parameters
        location
        scope: Scope()
        body
    return f

struct FunctionInfo:
    no_return: bool  # no_return attribute
    return_type: Type
    except_type: Type

struct FunctionDef:
    id: NodeId
    is_pub: bool
    info: FunctionInfo
    type_parameters: List[TypeParameter]
    this_parameter: Option[ParameterDef]
    parameters: List[ParameterDef]
    scope: Scope
    body: Statement
    location: Location

fn function_ref(function_def: FunctionDef, type_arguments: List[Type], location: Location) -> Expression:
    let kind = ExpressionKind.FunctionRef(function_def, type_arguments)
    let ty = get_function_type2(function_def, type_arguments)
    return Expression(kind, ty, location)

fn get_function_type(function_def: FunctionDef) -> Type:
    assert(condition: function_def.type_parameters.is_empty(), message: "Get function type can only be used on a non-generic function")
    let parameter_types: List[ParameterType] = List()
    for parameter in function_def.parameters:
        let label: Option[str] = Option.None()
        if parameter.label_is_optional:
            label = Option.None()
        else:
            label = Option.Some(parameter.id.name)
        parameter_types.append(ParameterType(label, ty: parameter.ty))
    let info = function_def.info
    return function_type(parameter_types, info)

fn get_function_type2(function_def: FunctionDef, type_arguments: List[Type]) -> Type:
    assert(condition: function_def.type_parameters.len() == type_arguments.len(), message: "{node_id_to_string(function_def.id)} -> Amount of type arguments must match amount of type parameters")
    let m: Dictionary[Type] = Dictionary()
    let tai = type_arguments.iter()
    for tp in function_def.type_parameters:
        let ta = option_unwrap(tai.next())
        m.insert(key: tp.id.name, value: ta)
    let parameter_types: List[ParameterType] = List()
    for parameter in function_def.parameters:
        let label: Option[str] = Option.None()
        if parameter.label_is_optional:
            label = Option.None()
        else:
            label = Option.Some(parameter.id.name)
        parameter_types.append(ParameterType(label, ty: subst(ty: parameter.ty, m)))
    let info = FunctionInfo:
        no_return: false
        return_type: subst(ty: function_def.info.return_type, m)
        except_type: subst(ty: function_def.info.except_type, m)
    return function_type(parameter_types, info)

fn parameter_def(name: str, id: int, label_is_optional: bool, ty: Type, location: Location) -> ParameterDef:
    return ParameterDef(id: NodeId(name, id), label_is_optional, ty, location)

struct ParameterDef:
    id: NodeId
    label_is_optional: bool
    ty: Type
    location: Location

fn variable(name: str, id: int, ty: Type, location: Location) -> Variable:
    return Variable(id: NodeId(name, id), ty, location)

struct Variable:
    id: NodeId
    ty: Type
    location: Location

struct ScopedBlock:
    scope: Scope
    body: Statement

fn scoped_block(body: Statement) -> ScopedBlock:
    return ScopedBlock(scope: Scope(), body)

struct Statement:
    location: Location
    kind: StatementKind
    is_terminator: bool

fn statement(kind: StatementKind, location: Location) -> Statement:
    return Statement(kind, location, is_terminator: false)

enum StatementKind:
    If(if_statement: IfStatement)
    While(while_statement: WhileStatement)
    Loop(loop_statement: LoopStatement)
    For(for_statement: ForStatement)
    Case(case_statement: CaseStatement)
    Switch(switch_statement: SwitchStatement)
    Let(let_statement: LetStatement)
    Try(try_statement: TryStatement)
    Compound(body: List[Statement])
    Expr(expression: Expression)
    Assignment(target: Expression, operator: Option[BinaryOperator], value: Expression)
    Return(value: Option[Expression])
    Raise(value: Expression)
    Unreachable
    Pass
    Break
    Continue

fn is_breakable(statement: Statement) -> bool:
    # Can we use break / continue within this statement?
    case statement.kind:
        While(x):
            return true
        Loop(x):
            return true
        For(x):
            return true
    else:
        return false

fn if_statement(condition: Expression, body: Statement, false_body: Statement, location: Location) -> Statement:
    let if_statement = IfStatement:
        condition: condition
        true_block: scoped_block(body)
        false_block: scoped_block(body: false_body)

    let kind = StatementKind.If(if_statement)
    return statement(kind, location)

struct IfStatement:
    condition: Expression
    true_block: ScopedBlock
    false_block: ScopedBlock

struct WhileStatement:
    condition: Expression
    block: ScopedBlock

fn while_statement(condition: Expression, body: Statement, location: Location) -> Statement:
    let while_statement = WhileStatement:
        condition
        block: scoped_block(body)
    let kind = StatementKind.While(while_statement)
    return statement(kind, location)

fn loop_statement(body: Statement, location: Location) -> Statement:
    let block = scoped_block(body)
    let kind = StatementKind.Loop(loop_statement: LoopStatement(block))
    return statement(kind, location)

struct LoopStatement:
    block: ScopedBlock

fn for_statement(iter_var: Variable, iter_value: Expression, body: Statement, location: Location) -> Statement:
    let for_statement = ForStatement:
        iter_var
        iter_value
        block: scoped_block(body)
    return statement(kind: StatementKind.For(for_statement), location)

struct ForStatement:
    iter_var: Variable
    iter_value: Expression
    block: ScopedBlock

fn try_statement(try_body: Statement, except_var: Variable, except_type: Type, except_body: Statement, location: Location) -> Statement:
    let try_statement = TryStatement:
        try_block: scoped_block(body: try_body)
        except_var
        except_type
        except_block: scoped_block(body: except_body)
    return statement(kind: StatementKind.Try(try_statement), location)

struct TryStatement:
    try_block: ScopedBlock
    except_var: Variable
    except_type: Type
    except_block: ScopedBlock

fn case_statement(value: Expression, arms: List[CaseArm], else_clause: Option[Statement], location: Location) -> Statement:
    let else_block: Option[ScopedBlock] = Option.None()
    case else_clause:
        Some(body):
            else_block = Option.Some(scoped_block(body))
        None:
            else_block = Option.None()
    let case_statement = CaseStatement(value, arms, else_block)
    return statement(kind: StatementKind.Case(case_statement), location)

struct CaseStatement:
    value: Expression
    arms: List[CaseArm]
    else_block: Option[ScopedBlock]

struct CaseArm:
    location: Location
    name: str
    variables: List[Variable]
    block: ScopedBlock

fn switch_statement(value: Expression, arms: List[SwitchArm], default_body: Statement, location: Location) -> Statement:
    let default_block = scoped_block(body: default_body)
    let switch_statement = SwitchStatement(value, arms, default_block)
    return statement(kind: StatementKind.Switch(switch_statement), location)

struct SwitchStatement:
    value: Expression
    arms: List[SwitchArm]
    default_block: ScopedBlock

struct SwitchArm:
    location: Location
    value: Expression
    block: ScopedBlock

fn let_statement(variable: Variable, type_hint: Option[Type], value: Expression, location: Location) -> Statement:
    let let_statement = LetStatement(variable, type_hint, value)
    let kind = StatementKind.Let(let_statement)
    return statement(kind, location)

struct LetStatement:
    variable: Variable
    type_hint: Option[Type]
    value: Expression

fn compound(inner: List[Statement], location: Location) -> Statement:
    if inner.len() == 1:
        return inner[0]
    else:
        let kind = StatementKind.Compound(body: inner)
        return statement(kind, location)

fn expression_statement(expr: Expression) -> Statement:
    let kind = StatementKind.Expr(expr)
    return statement(kind, location: expr.location)

fn assignment_statement(target: Expression, op: Option[BinaryOperator], value: Expression, location: Location) -> Statement:
    let kind = StatementKind.Assignment(target, op, value)
    return statement(kind, location)

fn return_statement(value: Option[Expression], location: Location) -> Statement:
    return statement(kind: StatementKind.Return(value), location)

fn raise_statement(value: Expression, location: Location) -> Statement:
    return statement(kind: StatementKind.Raise(value), location)

fn pass_statement(location: Location) -> Statement:
    return statement(kind: StatementKind.Pass(), location)

fn break_statement(location: Location) -> Statement:
    return statement(kind: StatementKind.Break(), location)

fn continue_statement(location: Location) -> Statement:
    return statement(kind: StatementKind.Continue(), location)

fn unreachable_statement(location: Location) -> Statement:
    return statement(kind: StatementKind.Unreachable(), location)

struct Expression:
    location: Location
    ty: Type
    kind: ExpressionKind

fn clone_expression(value: Expression) -> Expression:
    return Expression(kind: value.kind, ty: value.ty, location: value.location)

fn change_expression_to(expression: Expression, to: Expression):
    expression.kind = to.kind
    expression.ty = to.ty

enum ExpressionKind:
    Call(call: FunctionCall)
    GetAttr(base: Expression, name: str)
    GetIndex(base: Expression, indici: List[Expression])
    Binop(binop: BinopExpression)
    Unop(op: UnaryOperator, rhs: Expression)
    NameRef(name: str)
    VarRef(variable: Variable)
    FunctionRef(function: FunctionDef, type_arguments: List[Type])
    ParameterRef(parameter: ParameterDef)
    ExternFunctionRef(extern_function: ExternFunctionDef)
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
    ArrayLiteral2(value: Expression, size: Expression)
    TypeCast(typ: Type, value: Expression)
    ToString(value: Expression)
    Typ(ty: Type)
    TypeConstructor(tycon: TyCon)
    Variant(ty: Type, variant: EnumVariant)
    EnumLiteral(ty: Type, variant: EnumVariant, values: List[Expression])
    Undefined

struct LabeledExpression:
    location: Location
    name: Option[str]
    value: Expression

fn struct_literal(ty: Type, values: List[Expression], location: Location) -> Expression:
    return Expression(kind: ExpressionKind.StructLiteral(ty, values), ty, location)

fn union_literal(ty: Type, field: str, value: Expression, location: Location) -> Expression:
    return Expression(kind: ExpressionKind.UnionLiteral(ty, field, value), ty, location)

fn array_literal(values: List[Expression], location: Location) -> Expression:
    return Expression(kind: ExpressionKind.ArrayLiteral(values), ty: undefined_type(), location)

fn array_literal2(value: Expression, size: Expression, location: Location) -> Expression:
    return Expression(kind: ExpressionKind.ArrayLiteral2(value, size), ty: undefined_type(), location)

fn load_symbol(symbol: Symbol, ty: Type, location: Location) -> Expression:
    case symbol:
        ExternFunction(extern_function_def):
            return Expression(kind: ExpressionKind.ExternFunctionRef(extern_function_def), ty, location)
    else:
        return Expression(kind: ExpressionKind.LoadSymbol(symbol), ty, location)

fn parameter_ref(parameter_def: ParameterDef, location: Location) -> Expression:
    let ty = parameter_def.ty
    return Expression(kind: ExpressionKind.ParameterRef(parameter_def), ty, location)

fn call(callee: Expression, arguments: List[LabeledExpression], ty: Type, location: Location) -> Expression:
    let c = FunctionCall(callee, arguments)
    let kind = ExpressionKind.Call(c)
    return Expression(kind, ty, location)

fn get_attr(base: Expression, field: str, ty: Type, location: Location) -> Expression:
    let kind = ExpressionKind.GetAttr(base, field)
    return Expression(kind, ty, location)

fn get_attr_typed(value: Expression, attr: str, location: Location) -> Expression:
    let attr_ty = option_unwrap(get_field_type(ty: value.ty, attr))
    return get_attr(base: value, field: attr, ty: attr_ty, location)

fn call_method(base: Expression, method: str, arguments: List[LabeledExpression], location: Location) -> Expression:
    let callee = get_attr_typed(value: base, attr: method, location)
    let result_ty: Type = get_return_type_from_type(callee.ty)
    return call(callee, arguments, ty: result_ty, location)

struct FunctionCall:
    callee: Expression
    arguments: List[LabeledExpression]

fn subscript(base: Expression, indici: List[Expression], ty: Type, location: Location) -> Expression:
    let kind = ExpressionKind.GetIndex(base, indici)
    return Expression(kind, ty, location)

fn cast(value: Expression, to_type: Type, location: Location) -> Expression:
    let kind = ExpressionKind.TypeCast(to_type, value)
    return Expression(kind, ty: to_type, location)

#fn array_index(base: Expression, index: Expression, location: Location) -> Expression:
#    pass

# Reference a variable:
fn var_ref(variable: Variable, location: Location) -> Expression:
    let kind = ExpressionKind.VarRef(variable)
    return Expression(kind, ty: variable.ty, location)

# Reference a symbol:
fn name_ref(name: str, location: Location) -> Expression:
    let kind = ExpressionKind.NameRef(name)
    let ty = undefined_type()
    return Expression(kind, ty, location)

struct BinopExpression:
    lhs: Expression
    op: BinaryOperator
    rhs: Expression

enum BinaryOperator:
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

fn is_comparison_op(op: BinaryOperator) -> bool:
    case op:
        Less:
            return true
        LessEquals:
            return true
        Greater:
            return true
        GreaterEquals:
            return true
        Equals:
            return true
        NotEquals:
            return true
    else:
        return false

fn binop(lhs: Expression, op: BinaryOperator, rhs: Expression, ty: Type, location: Location) -> Expression:
    let b = BinopExpression(lhs, op, rhs)
    let kind = ExpressionKind.Binop(b)
    return Expression(kind, ty, location)

enum UnaryOperator:
    Not
    Minus

fn unop(op: UnaryOperator, value: Expression, ty: Type, location: Location) -> Expression:
    let kind = ExpressionKind.Unop(op, value)
    return Expression(kind, ty, location)

fn bool_literal(value: bool, location: Location) -> Expression:
    let kind = ExpressionKind.BoolLiteral(value)
    let ty = bool_type()
    return Expression(kind, ty, location)

fn integer_literal(value: int, location: Location) -> Expression:
    let kind = ExpressionKind.IntLiteral(value)
    let ty = int_type()
    return Expression(kind, ty, location)

fn float_literal(value: float, location: Location) -> Expression:
    let kind = ExpressionKind.FloatLiteral(value)
    let ty = float_type()
    return Expression(kind, ty, location)

fn string_literal(value: str, location: Location) -> Expression:
    let kind = ExpressionKind.StringLiteral(value)
    let ty = str_type()
    return Expression(kind, ty, location)

fn char_literal(value: char, location: Location) -> Expression:
    let kind = ExpressionKind.CharLiteral(value)
    let ty = char_type()
    return Expression(kind, ty, location)

fn to_string(value: Expression, location: Location) -> Expression:
    let kind = ExpressionKind.ToString(value)
    return Expression(kind, ty: str_type(), location)

fn undefined_value() -> Expression:
    let location = location_default()
    return Expression(kind: ExpressionKind.Undefined(), ty: undefined_type(), location)

fn print_ast2(module_set: ModuleSet):
    for module in module_set.modules:
        print_ast(module)

fn print_ast(module: Module):
    print("Module: " + module.name)
    let printer = AstPrinter()
    printer.indent()
    for imp in module.imports:
        case imp.kind:
            Self:
                printer.print2(txt: "import {imp.modname}")
            Names(names):
                printer.print2(txt: "from {imp.modname} import ..")
    let visitor = Visitor:
        data: printer
        on_definition: print_ast_definition
        on_type: print_ast_type
        on_statement: print_ast_statement
        on_expression: print_ast_expression
        on_node: print_ast_node
        
    visit_module(visitor, module)
    printer.dedent()

class AstPrinter:
    var indent_level: int = 0

    fn indent():
        indent_level += 1

    fn dedent():
        indent_level -= 1
    
    fn get_prefix() -> str:
        return str_repeat(text: "   ", count: indent_level)
    
    fn print2(txt: str):
        let prefix = get_prefix()
        print(prefix + txt)

fn print_ast_definition(printer: AstPrinter, definition: Definition, phase: VisitPhase):
    case phase:
        Pre:
            case definition:
                Function(func):
                    printer.print2(txt: "Func: {node_id_to_string(func.id)}")
                ExternFunction(efunc):
                    printer.print2(txt: "Extern func: {efunc.name}")
                Struct(struct_def):
                    let t = "Struct"
                    if struct_def.is_union:
                        t = "Union"
                    printer.print2(txt: "{t}: {node_id_to_string(struct_def.id)}")
                    for type_parameter in struct_def.type_parameters:
                        printer.print2(txt: "- TP {node_id_to_string(type_parameter.id)}")
                    for field in struct_def.fields:
                        printer.print2(txt: "- FIELD {field.name}")
                Enum(enum_def):
                    printer.print2(txt: "Enum: {node_id_to_string(enum_def.id)}")
                    for type_parameter in enum_def.type_parameters:
                        printer.print2(txt: "- TP {node_id_to_string(type_parameter.id)}")
                Class(class_def):
                    printer.print2(txt: "Class: {node_id_to_string(class_def.id)}")
                    for type_parameter in class_def.type_parameters:
                        printer.print2(txt: "- TP {node_id_to_string(type_parameter.id)}")
                Var(variable_def):
                    printer.print2(txt: "Var: {node_id_to_string(variable_def.variable.id)}")
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
    let txt = "?"
    case statement.kind:
        Expr(x):
            txt = "EXPR"
        Assignment(target, op, expr):
            case op:
                Some(op):
                    let op_txt = binary_op_to_str(op)
                    txt = "ASSIGN({op_txt})"
                None:
                    txt = "ASSIGN"
        If(x):
            txt = "IF"
        Return(x):
            txt = "RETURN"
        Raise(x):
            txt = "RAISE"
        Compound(x):
            txt = "COMPOUND"
        Pass:
            txt = "PASS"
        Break:
            txt = "BREAK"
        Continue:
            txt = "CONTINUE"
        Loop(loopy):
            txt = "LOOP"
        While(whilly):
            txt = "WHILE"
        For(f):
            txt = "FOR"
        Try(t):
            txt = "TRY"
        Case(f):
            txt = "CASE"
        Let(letty):
            txt = "LET {node_id_to_string(letty.variable.id)}"
        Switch(switchy):
            txt = "SWITCH"
        Unreachable:
            txt = "UNREACHABLE"
    
    if statement.is_terminator:
        txt = txt + " TERMINATES"
    return txt

fn print_ast_statement(printer: AstPrinter, statement: Statement, phase: VisitPhase):
    case phase:
        Pre:
            let txt = statement_to_string(statement)
            printer.print2(txt: "STMT {txt}")
            printer.indent()
        Post:
            printer.dedent()
    else:
        pass

fn expression_to_string(expression?: Expression) -> str:
    let txt = "?"
    case expression.kind:
        StringLiteral(value):
            txt = "String={value}"
        CharLiteral(value):
            txt = "Char={value}"
        IntLiteral(value):
            txt = "Integer={value}"
        FloatLiteral(val):
            txt = "Float={float_to_str(val)}"
        BoolLiteral(val):
            if val:
                txt = "Bool(true)"
            else:
                txt = "Bool(false)"
        Call(c):
            txt = "CALL"
        NameRef(name):
            txt = "REF({name})"
        LoadSymbol(symbol):
            txt = "LOAD_SYM({symbol_to_str(symbol)})"
        GetAttr(base, attr):
            txt = "GET-ATTR({attr})"
        GetIndex(base, indici):
            txt = "GET-INDEX"
        Undefined:
            txt = "UNDEFINED"
        Binop(op):
            let op_txt = binary_op_to_str(op: op.op)
            txt = "BINOP({op_txt})"
        Unop(op, value):
            let op_txt = unary_op_to_str(op)
            txt = "UNOP({op_txt})"
        VarRef(v):
            txt = "VAR-REF({node_id_to_string(v.id)})"
        FunctionRef(function, type_arguments):
            txt = "FN-{node_id_to_string(function.id)}"
            if not type_arguments.is_empty():
                txt = txt + types_to_string(typs: type_arguments)
        ExternFunctionRef(extern_function_def):
            txt = "extern-function:{extern_function_def.name}"
        ParameterRef(parameter_def):
            txt = "parameter:{node_id_to_string(parameter_def.id)}"
        StructLiteral(ty, values):
            txt = "STRUCT-LITERAL"
        UnionLiteral(ty, field, value):
            txt = "UNION-LITERAL field={field}"
        ClassLiteral(ty, arguments):
            txt = "CLASS-LITERAL"
        ArrayLiteral(values):
            txt = "ARRAY-LITERAL"
        ArrayLiteral2(value, size):
            txt = "ARRAY-LITERAL2"
        TypeCast(ty, value):
            txt = "TYPE-CAST"
        ToString(value):
            txt = "TOSTRING"
        Typ(ty):
            txt = "TYPE"
        TypeConstructor(tycon):
            txt = "TYPE-CONSTRUCTOR"
        Variant(ty, v):
            txt = "VARIANT"
        EnumLiteral(ty, v, values):
            txt = "ENUM-LITERAL"
    return txt

fn print_ast_expression(printer: AstPrinter, expression: Expression, phase: VisitPhase):
    case phase:
        Pre:
            let ty_txt = type_to_string(expression.ty)
            printer.print2(txt: "EXPR {expression_to_string(expression)} ---> {ty_txt}")
            printer.indent()
        Post:
            printer.dedent()
    else:
        pass

fn print_ast_node(printer: AstPrinter, node: VisitNode, phase: VisitPhase):
    pass

fn binary_op_to_str(op?: BinaryOperator) -> str:
    let op_txt = "?"
    case op:
        And:
            op_txt = "and"
        Or:
            op_txt = "or"
        Greater:
            op_txt = ">"
        GreaterEquals:
            op_txt = ">="
        Less:
            op_txt = "<"
        LessEquals:
            op_txt = "<="
        Equals:
            op_txt = "="
        NotEquals:
            op_txt = "!="
        BitAnd:
            op_txt = "bitand"
        BitXor:
            op_txt = "bitxor"
        BitOr:
            op_txt = "bitor"
        ShiftLeft:
            op_txt = "shl"
        ShiftRight:
            op_txt = "shr"
        Add:
            op_txt = "+"
        Sub:
            op_txt = "-"
        Mul:
            op_txt = "*"
        Div:
            op_txt = "/"
    return op_txt

fn unary_op_to_str(op: UnaryOperator) -> str:
    let op_txt = "?"
    case op:
        Not:
            op_txt = "not"
        Minus:
            op_txt = "-"
    return op_txt

struct Visitor[D]:
    data: D
    on_definition: fn(D, Definition, VisitPhase)
    on_type: fn(D, Type, VisitPhase)
    on_statement: fn(D, Statement, VisitPhase)
    on_expression: fn(D, Expression, VisitPhase)
    on_node: fn(D, VisitNode, VisitPhase)

enum VisitPhase:
    Pre
    Mid
    Post

enum VisitNode:
    Arm(arm: CaseArm)
    ScopeNode(scope: Scope)
    ModuleNode(module: Module)

fn visit_module_set[T](visitor: Visitor[T], module_set: ModuleSet):
    for module in module_set.modules:
        let module_node = VisitNode.ModuleNode(module)
        visit_module(visitor, module)
        visitor.on_node(data: visitor.data, module_node, phase: VisitPhase.Post())

fn visit_module[T](visitor: Visitor[T], module: Module):
    for definition in module.definitions:
        visit_definition(visitor, definition)


fn visit_definition[T](visitor: Visitor[T], definition: Definition):
    visitor.on_definition(a: visitor.data, definition, phase: VisitPhase.Pre())
    case definition:
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
            visit_statement(visitor, statement: function_def.body)
        ExternFunction(extern_function_def):
            for parameter_type in extern_function_def.parameter_types:
                visit_type(visitor, ty: parameter_type.ty)
            visit_type(visitor, ty: extern_function_def.return_type)
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
        Var(variable_def):
            visit_type(visitor, ty: variable_def.variable.ty)
            case variable_def.value:
                Some(v2):
                    visit_expression(visitor, expression: v2)
                None:
                    pass
    visitor.on_definition(data: visitor.data, definition, phase: VisitPhase.Post())

fn visit_type[T](visitor: Visitor[T], ty: Type):
    # print("Visit type")
    visitor.on_type(data: visitor.data, ty, phase: VisitPhase.Pre())
    case ty.kind:
        TypeExpression(expression):
            visit_expression(visitor, expression)
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
    else:
        pass
    visitor.on_type(data: visitor.data, ty, phase: VisitPhase.Post())

fn visit_statement[T](visitor: Visitor[T], statement: Statement):
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
            let arm_node = VisitNode.ScopeNode(if_statement.true_block.scope)
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

fn visit_expression[T](visitor: Visitor[T], expression: Expression):
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
        ArrayLiteral2(value, size):
            visit_expression(visitor, expression: value)
            visit_expression(visitor, expression: size)
        ClassLiteral(ty, arguments):
            visit_type(visitor, ty)
            for arg in arguments:
                visit_expression(visitor, expression: arg.value)
        TypeCast(ty, value):
            visit_type(visitor, ty)
            visit_expression(visitor, expression: value)
        ToString(value):
            visit_expression(visitor, expression: value)
        Typ(ty):
            visit_type(visitor, ty)
        TypeConstructor(tycon):
            pass
        Variant(ty, v):
            pass
        EnumLiteral(ty, v, values):
            for value in values:
                visit_expression(visitor, expression: value)
    else:
        pass

    visitor.on_expression(data: visitor.data, expression, phase: VisitPhase.Post())

