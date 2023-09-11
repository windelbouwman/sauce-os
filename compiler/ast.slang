
from std import print, float_to_str
from strlib import str_repeat
from utils import panic, assert
from location import Location, location_default
from datatypes import List, Option, Dictionary, option_unwrap, option_is_some

# Name coupled with global unique ID:
struct NodeId:
    name: str
    id: int

fn node_id_equal(node_id1: NodeId, node_id2: NodeId) -> bool:
    if node_id1.id == node_id2.id:
        return true
    else:
        return false

fn node_id_to_string(id: NodeId) -> str:
    return "{id.name}${id.id}"

# TODO: implement type-defs!
struct Type:
    stub: int
    kind: TypeKind

fn new_type(kind: TypeKind) -> Type:
    return Type(stub: 0, kind)

fn types_to_string(typs: List[Type]) -> str:
    let txt = "["
    for ty in typs:
        txt = txt + type_to_string(ty) + ","
    txt = txt + "]"
    return txt

fn type_to_string(ty?: Type) -> str:
    case ty.kind:
        Str:
            return "STR"
        Int:
            return "INT"
        Bool:
            return "BOOL"
        Float:
            return "FLOAT"
        Void:
            return "VOID"
        TypeExpression(expr):
            return "TYPE-EXPR"
        Function(parameter_types, return_type):
            return "FUNC-TYPE({types_to_string(typs: parameter_types)},{type_to_string(return_type)})"
        Undefined:
            return "UNDEFINED"
        TypeParam(param):
            return "TYPE-PARAM({node_id_to_string(id: param.id)})"
        TypeVar(v):
            case v.ty:
                None:
                    return "TYPE-VAR(id={v.unique})"
                Some(ty_assigned):
                    return "TYPE-VAR(id={v.unique},{type_to_string(ty_assigned)})"
        App(tycon, type_arguments):
            let args = types_to_string(typs: type_arguments)
            return "APP({tycon_to_str(tycon)}, {args})"

fn change_type_to(ty: Type, ty2: Type):
    # Adjust ty to ty2
    ty.kind = ty2.kind

fn apply_tycon(tycon: TyCon, type_arguments: List[Type]) -> Type:
    # if type_arguments
    let type_parameters = tycon_get_type_parameters(tycon)
    # Check lengths!
    assert(condition: type_parameters.len() == type_arguments.len(), message: "type arguments does not match amount of type parameters")
    return new_type(kind: TypeKind.App(tycon, type_arguments))

fn subst(ty: Type, m: Dictionary[Type]) -> Type:
    case ty.kind:
        TypeParam(p):
            case m.get(key: p.id.name):
                Some(ty3):
                    return ty3
                None:
                    return ty
        Function(parameter_types, return_type):
            return function_type(parameter_types: subst_many(typs: parameter_types, m), return_type: subst(ty: return_type, m))
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
    assert(condition: type_parameters.len() == type_arguments.len(), message: "amount of type parameters and type arguments must be equal")
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

fn is_void_type(ty?: Type) -> bool:
    case ty.kind:
        Void:
            return true
    else:
        return false

fn is_int_type(ty?: Type) -> bool:
    case ty.kind:
        Int:
            return true
    else:
        return false

fn is_str_type(ty?: Type) -> bool:
    case ty.kind:
        Str:
            return true
    else:
        return false

fn is_bool_type(ty?: Type) -> bool:
    case ty.kind:
        Bool:
            return true
    else:
        return false

fn is_float_type(ty?: Type) -> bool:
    case ty.kind:
        Float:
            return true
    else:
        return false

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
        Function(p,r):
            return true
    else:
        return false

fn get_parameter_types_from_type(ty?: Type) -> List[Type]:
    case ty.kind:
        Function(p, r):
            return p
    else:
        panic("Type must be function type")

fn get_return_type_from_type(ty?: Type) -> Type:
    case ty.kind:
        Function(p, r):
            return r
    else:
        panic("Type must be function type")

fn get_enum_variant(ty: Type, attr: str) -> Option[EnumVariant]:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Enum(enum_def):
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
            else:
                panic("get_enum_variant: type must be enum")
    else:
        panic("get_enum_variant: type must be enum")

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

fn get_struct_name_from_type(ty: Type) -> str:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Struct(struct_def):
                    return struct_def.id.name
            else:
                panic("No struct type")
    else:
        panic("No struct type")

fn has_field(ty: Type, attr: str) -> bool:
    return option_is_some(get_field_type(ty, attr))

fn get_field_type(ty: Type, attr: str) -> Option[Type]:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Struct(s):
                    case s.scope.lookup(name: attr):
                        Some(sym):
                            let m = create_subst_mapping(type_parameters: s.type_parameters, type_arguments)
                            case sym:
                                Field(f):
                                    return Option.Some(subst(ty: f.ty, m))
                            else:
                                panic("Struct field must be ")
                        None:
                            return Option.None()
                Class(c):
                    case c.scope.lookup(name: attr):
                        Some(sym):
                            let m = create_subst_mapping(type_parameters: c.type_parameters, type_arguments)
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
                panic("No class")
    else:
        panic("No class")

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


fn get_return_type(ty?: Type) -> Type:
    case ty.kind:
        Function(args, rty):
            return rty
    else:
        panic("Must be function type")

fn get_tycon(ty?: Type) -> TyCon:
    case ty.kind:
        App(tycon, args):
            return tycon
    else:
        panic("Must be App type")

fn get_type_arguments(ty?: Type) -> List[Type]:
    case ty.kind:
        App(tycon, args):
            return args
    else:
        panic("Must be App type")

enum TypeKind:
    Undefined
    Bool
    Int
    Str
    Float
    Void
    TypeExpression(expression: Expression)
    Function(parameter_types: List[Type], return_type: Type)
    TypeParam(type_parameter: TypeParameter)
    TypeVar(type_variable: TypeVariable)
    
    # Application of a type-constructor:
    App(tycon: TyCon,type_arguments: List[Type])

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
            return "struct({node_id_to_string(id: struct_def.id)})"
        Enum(enum_def):
            return "enum({node_id_to_string(id: enum_def.id)})"
        Class(class_def):
            return "class({node_id_to_string(id: class_def.id)})"

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

fn bool_type() -> Type:
    return new_type(kind: TypeKind.Bool())

fn int_type() -> Type:
    return new_type(kind: TypeKind.Int())

fn float_type() -> Type:
    return new_type(kind: TypeKind.Float())

fn str_type() -> Type:
    return new_type(kind: TypeKind.Str())

fn undefined_type() -> Type:
    return new_type(kind: TypeKind.Undefined())

fn type_expression(expr: Expression) -> Type:
    return new_type(kind: TypeKind.TypeExpression(expr))

fn function_type(parameter_types: List[Type], return_type: Type) -> Type:
    return new_type(kind: TypeKind.Function(parameter_types, return_type))

fn type_parameter_ref(type_parameter: TypeParameter) -> Type:
    return new_type(kind: TypeKind.TypeParam(type_parameter))

fn new_type_var_ref(type_var: TypeVariable) -> Type:
    return new_type(kind: TypeKind.TypeVar(type_var))

fn new_type_var(unique: int) -> TypeVariable:
    return TypeVariable(unique, ty: Option.None())

fn type_var_equals(type_var1: TypeVariable, type_var2: TypeVariable) -> bool:
    return type_var1.unique == type_var2.unique

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

fn module_define_symbol(module: Module, definition: Definition):
    module.definitions.append(definition)
    case definition:
        Var(variable):
            module.scope.define(name: variable.variable.id.name, symbol: Symbol.Var(variable: variable.variable))
        Function(function):
            module.scope.define(name: function.id.name, symbol: Symbol.Function(function))
        ExternFunction(external_function):
            module.scope.define(name: external_function.name, symbol: Symbol.ExternFunction(external_function))
        Enum(enum_def):
            module.scope.define(name: enum_def.id.name, symbol: Symbol.TypeConstructor(tycon: TyCon.Enum(enum_def)))
        Struct(struct_def):
            module.scope.define(name: struct_def.id.name, symbol: Symbol.TypeConstructor(tycon: TyCon.Struct(struct_def)))
        Class(class_def):
            module.scope.define(name: class_def.id.name, symbol: Symbol.TypeConstructor(tycon: TyCon.Class(class_def)))

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
    name: str
    parameter_types: List[Type]
    return_type: Type

fn extern_function_type(func: ExternFunctionDef) -> Type:
    return function_type(parameter_types: func.parameter_types, return_type: func.return_type)

class Scope:
    var symbols: Dictionary[Symbol] = Dictionary()

    fn define(name: str, symbol: Symbol):
        this.symbols.insert(key: name, value: symbol)
    
    fn is_defined(name: str) -> bool:
        # Check if given name is defined.
        return option_is_some(this.lookup(name))

    fn lookup(name: str) -> Option[Symbol]:
        return this.symbols.get(key: name)

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
            return "function:{node_id_to_string(id: f.id)}"
        ExternFunction(f):
            return "extern-function:{f.name}"
        Parameter(p):
            return "parameter:{node_id_to_string(id: p.id)}"
        Var(v):
            return "var:{node_id_to_string(id: v.id)}"
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
    location: Location
    variable: Variable
    value: Option[Expression]
    
fn new_type_parameter(name: str, id: int, location: Location) -> TypeParameter:
    return TypeParameter(id: NodeId(name, id), location)

struct TypeParameter:
    id: NodeId
    location: Location

fn struct_def(name: str, id: int, type_parameters: List[TypeParameter], fields: List[StructField], location: Location) -> StructDef:
    let s = StructDef:
        id: NodeId(name, id)
        type_parameters: type_parameters
        fields: fields
        location: location
        scope: Scope()
    return s

struct StructDef:
    id: NodeId
    type_parameters: List[TypeParameter]
    fields: List[StructField]
    location: Location
    scope: Scope

class StructBuilder:
    var nodeId: NodeId = NodeId(name: "", id: 0)
    var location: Location = location_default()
    var type_parameters: List[TypeParameter] = List()
    var fields: List[StructField] = List()

    fn set_name(name: str):
        this.nodeId.name = name
    
    fn set_id(id: int):
        this.nodeId.id = id

    fn add_type_parameter(name: str, id: int, location: Location) -> Type:
        let type_parameter = new_type_parameter(name, id, location)
        this.type_parameters.append(type_parameter)
        return type_parameter_ref(type_parameter)

    fn add_field(name: str, ty: Type, location: Location):
        this.fields.append(StructField(name, ty, location))

    fn finish() -> StructDef:
        let scope = Scope()
        for field in this.fields:
            scope.define(name: field.name, symbol: Symbol.Field(field))
        let struct_def = StructDef:
            id: this.nodeId
            type_parameters: this.type_parameters
            fields: this.fields
            location: this.location
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
    location: Location
    payload: List[Type]

struct ClassDef:
    id: NodeId
    location: Location
    type_parameters: List[TypeParameter]
    definitions: List[Definition]
    scope: Scope

fn function_def(name: str, id: int, type_parameters: List[TypeParameter], this_parameter: Option[ParameterDef], parameters: List[ParameterDef], return_type: Type, except_type: Type, body: Statement, location: Location) -> FunctionDef:
    let f = FunctionDef:
        id: NodeId(name, id)
        is_pub: true
        type_parameters
        this_parameter
        parameters
        return_type
        except_type
        location
        scope: Scope()
        body
    return f

struct FunctionDef:
    id: NodeId
    is_pub: bool
    type_parameters: List[TypeParameter]
    this_parameter: Option[ParameterDef]
    parameters: List[ParameterDef]
    return_type: Type
    except_type: Type
    scope: Scope
    body: Statement
    location: Location

fn get_function_type(function_def: FunctionDef) -> Type:
    let m: Dictionary[Type] = Dictionary()
    let unique_id = 1
    for tp in function_def.type_parameters:
        let type_var = new_type_var(unique: unique_id)
        m.insert(key: tp.id.name, value: new_type_var_ref(type_var))
        unique_id += 1
    let parameter_types: List[Type] = List()
    for p in function_def.parameters:
        parameter_types.append(subst(ty: p.ty, m))
    return function_type(parameter_types, return_type: subst(ty: function_def.return_type, m))

fn parameter_def(name: str, id: int, label_is_optional: bool, ty: Type, location: Location) -> ParameterDef:
    return ParameterDef(id: NodeId(name, id), label_is_optional, ty, location)

struct ParameterDef:
    id: NodeId
    label_is_optional: bool
    ty: Type
    location: Location

fn variable(name: str, id: int, ty: Type) -> Variable:
    return Variable(id: NodeId(name, id), ty)

struct Variable:
    id: NodeId
    ty: Type

struct Statement:
    location: Location
    kind: StatementKind

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
    Pass
    Break
    Continue

fn if_statement(condition: Expression, body: Statement, false_body: Statement, location: Location) -> Statement:
    let i = IfStatement:
        condition: condition
        true_body: body
        false_body: false_body

    let kind = StatementKind.If(if_statement: i)
    return Statement(kind, location)

struct IfStatement:
    condition: Expression
    true_body: Statement
    false_body: Statement

struct WhileStatement:
    condition: Expression
    body: Statement

fn while_statement(condition: Expression, body: Statement, location: Location) -> Statement:
    let while_statement = WhileStatement(condition, body)
    let kind = StatementKind.While(while_statement)
    return Statement(kind, location)

fn loop_statement(body: Statement, location: Location) -> Statement:
    let kind = StatementKind.Loop(loop_statement: LoopStatement(body))
    return Statement(kind, location)

struct LoopStatement:
    body: Statement

fn for_statement(iter_var: str, iter_var_id: int, iter_value: Expression, body: Statement, location: Location) -> Statement:
    let v = variable(name: iter_var, id: iter_var_id, ty: undefined_type())
    let for_statement = ForStatement(iter_var: v, iter_value, body)
    return Statement(kind: StatementKind.For(for_statement), location)

struct ForStatement:
    iter_var: Variable
    iter_value: Expression
    body: Statement

fn try_statement(try_body: Statement, except_param: ParameterDef, except_body: Statement, location: Location) -> Statement:
    let try_statement = TryStatement(try_body, except_param, except_body)
    return Statement(kind: StatementKind.Try(try_statement), location)

struct TryStatement:
    try_body: Statement
    except_param: ParameterDef
    except_body: Statement

struct CaseStatement:
    value: Expression
    arms: List[CaseArm]
    else_clause: Option[Statement]

struct CaseArm:
    location: Location
    name: str
    variables: List[Variable]
    scope: Scope
    body: Statement

fn switch_statement(value: Expression, arms: List[SwitchArm], default_body: Statement, location: Location) -> Statement:
    let switch_statement = SwitchStatement(value, arms, default_body)
    return Statement(kind: StatementKind.Switch(switch_statement), location)

struct SwitchStatement:
    value: Expression
    arms: List[SwitchArm]
    default_body: Statement

struct SwitchArm:
    location: Location
    value: Expression
    body: Statement

fn let_statement(variable: Variable, type_hint: Option[Type], value: Expression, location: Location) -> Statement:
    let let_statement = LetStatement(variable, type_hint, value)
    let kind = StatementKind.Let(let_statement)
    return Statement(kind, location)

struct LetStatement:
    variable: Variable
    type_hint: Option[Type]
    value: Expression

fn compound(inner: List[Statement], location: Location) -> Statement:
    if inner.len() == 1:
        return inner.get(index: 0)
    else:
        let kind = StatementKind.Compound(body: inner)
        return Statement(kind, location)

fn expression_statement(expr: Expression) -> Statement:
    let kind = StatementKind.Expr(expr)
    return Statement(kind, location: expr.location)

fn assignment_statement(target: Expression, op: Option[BinaryOperator], value: Expression, location: Location) -> Statement:
    let kind = StatementKind.Assignment(target, op, value)
    return Statement(kind, location)

fn return_statement(value: Option[Expression], location: Location) -> Statement:
    return Statement(kind: StatementKind.Return(value), location)

fn raise_statement(value: Expression, location: Location) -> Statement:
    return Statement(kind: StatementKind.Raise(value), location)

fn pass_statement(location: Location) -> Statement:
    return Statement(kind: StatementKind.Pass(), location)

fn break_statement(location: Location) -> Statement:
    return Statement(kind: StatementKind.Break(), location)

fn continue_statement(location: Location) -> Statement:
    return Statement(kind: StatementKind.Continue(), location)

struct Expression:
    location: Location
    ty: Type
    kind: ExpressionKind

fn clone_expression(value: Expression) -> Expression:
    return Expression(kind: value.kind, ty: value.ty, location: value.location)

enum ExpressionKind:
    Call(call: FunctionCall)
    GetAttr(base: Expression, name: str)
    GetIndex(base: Expression, indici: List[Expression])
    Binop(binop: BinopExpression)
    Unop(op: UnaryOperator, rhs: Expression)
    NameRef(name: str)
    VarRef(variable: Variable)
    LoadSymbol(symbol: Symbol)
    IntLiteral(value: int)
    FloatLiteral(value: float)
    StringLiteral(value: str)
    BoolLiteral(value: bool)
    StructLiteral(ty: Type, values: List[Expression])
    ClassLiteral(typ: Type, arguments: List[LabeledExpression])
    TypeCast(typ: Type, value: Expression)
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

fn load_symbol(symbol: Symbol, ty: Type, location: Location) -> Expression:
    return Expression(kind: ExpressionKind.LoadSymbol(symbol), ty, location)

fn call(callee: Expression, arguments: List[LabeledExpression], ty: Type, location: Location) -> Expression:
    let c = FunctionCall(callee, arguments)
    let kind = ExpressionKind.Call(c)
    return Expression(kind, ty, location)

fn get_attr(base: Expression, field: str, ty: Type, location: Location) -> Expression:
    let kind = ExpressionKind.GetAttr(base, field)
    return Expression(kind, ty, location)

struct FunctionCall:
    callee: Expression
    arguments: List[LabeledExpression]

fn subscript(base: Expression, indici: List[Expression], ty: Type, location: Location) -> Expression:
    let kind = ExpressionKind.GetIndex(base, indici)
    return Expression(kind, ty, location)

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

fn undefined_value() -> Expression:
    let location = location_default()
    return Expression(kind: ExpressionKind.Undefined(), ty: undefined_type(), location)

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
        this.indent_level += 1

    fn dedent():
        this.indent_level -= 1
    
    fn get_prefix() -> str:
        return str_repeat(text: "   ", count: this.indent_level)
    
    fn print2(txt: str):
        let prefix = this.get_prefix()
        print(prefix + txt)

fn print_ast_definition(printer: AstPrinter, definition: Definition, phase: VisitPhase):
    case phase:
        Pre:
            case definition:
                Function(func):
                    printer.print2(txt: "Func: {node_id_to_string(id: func.id)}")
                ExternFunction(efunc):
                    printer.print2(txt: "Extern func: {efunc.name}")
                Struct(struct_def):
                    printer.print2(txt: "Struct: {node_id_to_string(id: struct_def.id)}")
                Enum(e):
                    printer.print2(txt: "Enum: {node_id_to_string(id: e.id)}")
                Class(class_def):
                    printer.print2(txt: "Class: {node_id_to_string(id: class_def.id)}")
                Var(v):
                    printer.print2(txt: "Var: {node_id_to_string(id: v.variable.id)}")
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
            txt = "LET"
        Switch(switchy):
            txt = "SWITCH"
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

fn expression_to_string(expression: Expression) -> str:
    let txt = "?"
    case expression.kind:
        StringLiteral(val):
            txt = "String={val}"
        IntLiteral(val):
            txt = "Integer={val}"
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
            txt = "VAR-REF({node_id_to_string(id: v.id)})"
        StructLiteral(ty, values):
            txt = "STRUCT-LITERAL"
        ClassLiteral(ty, arguments):
            txt = "CLASS-LITERAL"
        TypeCast(ty, value):
            txt = "TYPE-CAST"
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
            printer.print2(txt: "EXPR {expression_to_string(expression)}")
            printer.indent()
        Post:
            printer.dedent()
    else:
        pass

fn print_ast_node(printer: AstPrinter, node: VisitNode, phase: VisitPhase):
    pass

fn binary_op_to_str(op: BinaryOperator) -> str:
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

fn visit_module[T](visitor: Visitor[T], module: Module):
    for definition in module.definitions:
        visit_definition(visitor, definition)


fn visit_definition[T](visitor: Visitor[T], definition: Definition):
    visitor.on_definition(a: visitor.data, definition, phase: VisitPhase.Pre())
    case definition:
        Function(func):
            # print("VISIT {func.name}")
            for parameter in func.parameters:
                visit_type(visitor, ty: parameter.ty)
            visit_type(visitor, ty: func.return_type)
            visit_statement(visitor, statement: func.body)
        ExternFunction(e):
            pass
        Enum(e):
            for variant in e.variants:
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
        Function(parameter_types, return_type):
            for parameter_type in parameter_types:
                visit_type(visitor, ty: parameter_type)
            visit_type(visitor, ty: return_type)
    else:
        pass
    visitor.on_type(data: visitor.data, ty, phase: VisitPhase.Post())

fn visit_statement[T](visitor: Visitor[T], statement: Statement):
    visitor.on_statement(data: visitor.data, statement, phase: VisitPhase.Pre())
    case statement.kind:
        Pass:
            pass
        Let(let_statement):
            case let_statement.type_hint:
                Some(ty):
                    visit_type(visitor, ty)
                None:
                    pass
            visit_expression(visitor, expression: let_statement.value)
        If(if_statement):
            visit_expression(visitor, expression: if_statement.condition)
            visit_statement(visitor, statement: if_statement.true_body)
            visit_statement(visitor, statement: if_statement.false_body)
        While(while_statement):
            visit_expression(visitor, expression: while_statement.condition)
            visit_statement(visitor, statement: while_statement.body)
        Loop(loop_statement):
            visit_statement(visitor, statement: loop_statement.body)
        Switch(switch_statement):
            visit_expression(visitor, expression: switch_statement.value)
            # TODO: visit arms!
        For(for_statement):
            visit_expression(visitor, expression: for_statement.iter_value)
            visitor.on_statement(data: visitor.data, statement, phase: VisitPhase.Mid())
            visit_statement(visitor, statement: for_statement.body)
        Try(try_statement):
            visit_statement(visitor, statement: try_statement.try_body)
            visit_type(visitor, ty: try_statement.except_param.ty)
            visit_statement(visitor, statement: try_statement.except_body)
        Case(case_statement):
            visit_expression(visitor, expression: case_statement.value)
            visitor.on_statement(data: visitor.data, statement, phase: VisitPhase.Mid())
            for arm in case_statement.arms:
                let arm_node = VisitNode.Arm(arm)
                visitor.on_node(data: visitor.data, arm_node, phase: VisitPhase.Pre())
                visit_statement(visitor, statement: arm.body)
                visitor.on_node(data: visitor.data, arm_node, phase: VisitPhase.Post())
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
        Break:
            pass
        Continue:
            pass
    visitor.on_statement(data: visitor.data, statement, phase: VisitPhase.Post())

fn visit_expression[T](visitor: Visitor[T], expression: Expression):
    visitor.on_expression(data: visitor.data, expression, phase: VisitPhase.Pre())

    case expression.kind:
        BoolLiteral(v):
            pass
        IntLiteral(v):
            pass
        FloatLiteral(val):
            pass
        StringLiteral(v):
            pass
        Undefined:
            pass
        NameRef(v):
            # print("name-ref -> {v}")
            pass
        LoadSymbol(s):
            pass
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
        VarRef(v):
            pass
        StructLiteral(ty, values):
            visit_type(visitor, ty)
            for value in values:
                visit_expression(visitor, expression: value)
        ClassLiteral(ty, arguments):
            visit_type(visitor, ty)
            for arg in arguments:
                visit_expression(visitor, expression: arg.value)
        TypeCast(ty, value):
            visit_type(visitor, ty)
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

    visitor.on_expression(data: visitor.data, expression, phase: VisitPhase.Post())

