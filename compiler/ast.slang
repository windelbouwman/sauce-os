
from std import print
from utils import panic, assert
from location import Location, new_location
from datatypes import List, Option, Dictionary, option_unwrap, option_is_some

# Name coupled with global unique ID:
struct NodeId:
    name: str
    id: int

fn new_node_id(name: str, id: int) -> NodeId:
    let n = NodeId:
        name: name
        id: id
    return n

fn node_id_equal(node_id1: NodeId, node_id2: NodeId) -> bool:
    if node_id1.id == node_id2.id:
        return true
    else:
        return false

# TODO: implement type-defs!
struct MyType:
    stub: int
    kind: TypeKind

fn new_type(kind: TypeKind) -> MyType:
    let t = MyType:
        stub: 0
        kind: kind
    return t

fn types_to_string(typs: List[MyType]) -> str:
    let txt = "["
    for ty in typs:
        txt = txt + type_to_string(ty) + ","
    txt = txt + "]"
    return txt

fn type_to_string(ty: MyType) -> str:
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
            return "FUNC-TYPE({types_to_string(parameter_types)},{type_to_string(return_type)})"
        Undefined:
            return "UNDEFINED"
        TypeParam(param):
            return "TYPE-PARAM({param.node_id.name},{param.node_id.id})"
        TypeVar(v):
            case v.ty:
                None:
                    return "TYPE-VAR(id={v.unique})"
                Some(ty_assigned):
                    return "TYPE-VAR(id={v.unique},{type_to_string(ty_assigned)})"
        App(tycon, type_arguments):
            let args = types_to_string(type_arguments)
            return "APP({tycon_to_str(tycon)}, {args})"

fn change_type_to(ty: MyType, ty2: MyType):
    # Adjust ty to ty2
    ty.kind = ty2.kind

fn apply_tycon(tycon: TyCon, type_arguments: List[MyType]) -> MyType:
    # if type_arguments
    let type_parameters = tycon_get_type_parameters(tycon)
    # Check lengths!
    assert(type_parameters.len() == type_arguments.len(), "type arguments does not match amount of type parameters")
    return new_type(TypeKind.App(tycon, type_arguments))

fn subst(ty: MyType, m: Dictionary[MyType]) -> MyType:
    case ty.kind:
        TypeParam(p):
            case m.get(p.node_id.name):
                Some(ty3):
                    return ty3
                None:
                    return ty
        Function(parameter_types, return_type):
            return function_type(subst_many(parameter_types, m), subst(return_type, m))
        App(tycon, type_arguments):
            return apply_tycon(tycon, subst_many(type_arguments, m))
    else:
        return ty

fn subst_many(typs: List[MyType], m: Dictionary[MyType]) -> List[MyType]:
    let typs2: List[MyType] = List()
    for ty in typs:
        typs2.append(subst(ty, m))
    return typs2

fn create_subst_mapping(type_parameters: List[TypeParameter], type_arguments: List[MyType]) -> Dictionary[MyType]:
    assert(type_parameters.len() == type_arguments.len(), "amount of type parameters and type arguments must be equal")
    let m: Dictionary[MyType] = Dictionary()
    let tpi = type_parameters.iter()
    for ty in type_arguments:
        let tp = option_unwrap(tpi.next())
        m.insert(tp.node_id.name, ty)
    return m


fn is_enum_type(ty: MyType) -> bool:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Enum(x):
                    return true
            else:
                return false
    else:
        return false

fn is_void_type(ty: MyType) -> bool:
    case ty.kind:
        Void:
            return true
    else:
        return false

fn is_int_type(ty: MyType) -> bool:
    case ty.kind:
        Int:
            return true
    else:
        return false

fn is_str_type(ty: MyType) -> bool:
    case ty.kind:
        Str:
            return true
    else:
        return false

fn is_bool_type(ty: MyType) -> bool:
    case ty.kind:
        Bool:
            return true
    else:
        return false

fn is_float_type(ty: MyType) -> bool:
    case ty.kind:
        Float:
            return true
    else:
        return false

fn is_tycon_app_type(ty: MyType) -> bool:
    case ty.kind:
        App(tycon, args):
            return true
    else:
        return false

fn is_type_parameter_type(ty: MyType) -> bool:
    case ty.kind:
        TypeParam(p):
            return true
    else:
        return false

fn is_type_var_type(ty: MyType) -> bool:
    case ty.kind:
        TypeVar(v):
            return true
    else:
        return false

fn get_type_var_from_type(ty: MyType) -> TypeVariable:
    case ty.kind:
        TypeVar(v):
            return v
    else:
        panic("Type must be type variable reference")

fn deref_type_var(ty: MyType) -> MyType:
    case ty.kind:
        TypeVar(type_var):
            case type_var.ty:
                None:
                    panic("Must be assigned type!")
                Some(t):
                    return t
    else:
        return ty


fn get_type_parameter_from_type(ty: MyType) -> TypeParameter:
    case ty.kind:
        TypeParam(p):
            return p
    else:
        panic("Type must be type parameter")

fn is_function_type(ty: MyType) -> bool:
    case ty.kind:
        Function(p,r):
            return true
    else:
        return false

fn get_parameter_types_from_type(ty: MyType) -> List[MyType]:
    case ty.kind:
        Function(p, r):
            return p
    else:
        panic("Type must be function type")

fn get_return_type_from_type(ty: MyType) -> MyType:
    case ty.kind:
        Function(p, r):
            return r
    else:
        panic("Type must be function type")

fn get_enum_variant(ty: MyType, attr: str) -> Option[EnumVariant]:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Enum(x):
                    case x.scope.lookup(attr):
                        Some(s):
                            case s:
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

fn get_subst_map(ty: MyType) -> Dictionary[MyType]:
    case ty.kind:
        App(tycon, type_arguments):
            return create_subst_mapping(tycon_get_type_parameters(tycon), type_arguments)
    else:
        panic("Must be App type")

fn get_variant_payload_types(ty: MyType, v: EnumVariant) -> List[MyType]:
    let m = get_subst_map(ty)
    let payload = subst_many(v.payload, m)
    return payload

fn get_field_types(ty: MyType) -> List[MyType]:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Struct(struct_def):
                    let m = create_subst_mapping(struct_def.type_parameters, type_arguments)
                    let field_types: List[MyType] = List()
                    for field in struct_def.fields:
                        field_types.append(subst(field.ty, m))
                    return field_types
            else:
                panic("Type without fields")
    else:
        panic("Type without fields")

fn has_field(ty: MyType, attr: str) -> bool:
    return option_is_some(get_field_type(ty, attr))

fn get_field_type(ty: MyType, attr: str) -> Option[MyType]:
    case ty.kind:
        App(tycon, type_arguments):
            case tycon:
                Struct(s):
                    case s.scope.lookup(attr):
                        Some(sym):
                            let m = create_subst_mapping(s.type_parameters, type_arguments)
                            case sym:
                                Field(f):
                                    return Option.Some(subst(f.ty, m))
                            else:
                                panic("Struct field must be ")
                        None:
                            return Option.None()
                Class(c):
                    case c.scope.lookup(attr):
                        Some(sym):
                            let m = create_subst_mapping(c.type_parameters, type_arguments)
                            case sym:
                                Function(f):
                                    return Option.Some(subst(get_function_type(f), m))
                                Var(v):
                                    return Option.Some(subst(v.ty, m))
                            else:
                                panic("class must contain func/vars")
                        None:
                            return Option.None()
            else:
                return Option.None()
    else:
        return Option.None()

fn get_return_type(ty: MyType) -> MyType:
    case ty.kind:
        Function(args, rty):
            return rty
    else:
        panic("Must be function type")

fn get_tycon(ty: MyType) -> TyCon:
    case ty.kind:
        App(tycon, args):
            return tycon
    else:
        panic("Must be App type")

fn get_type_arguments(ty: MyType) -> List[MyType]:
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
    TypeExpression(Expression)
    Function(List[MyType], MyType)
    TypeParam(TypeParameter)
    TypeVar(TypeVariable)
    
    # Application of a type-constructor:
    App(TyCon,List[MyType])

struct TypeVariable:
    unique: int
    ty: Option[MyType]  # assigned type

enum TyCon:
    Struct(StructDef)
    Enum(EnumDef)
    Class(ClassDef)

fn tycon_to_str(tycon: TyCon) -> str:
    case tycon:
        Struct(struct_def):
            return "struct({struct_def.node_id.name},{struct_def.node_id.id})"
        Enum(enum_def):
            return "enum({enum_def.name})"
        Class(class_def):
            return "class({class_def.node_id.name},{class_def.node_id.id})"

fn tycon_equal(tycon1: TyCon, tycon2: TyCon) -> bool:
    case tycon1:
        Struct(struct_def1):
            case tycon2:
                Struct(struct_def2):
                    return node_id_equal(struct_def1.node_id, struct_def2.node_id)
            else:
                return false
        Enum(enum_def1):
            case tycon2:
                Enum(enum_def2):
                    return enum_def1.name == enum_def2.name
            else:
                return false
        Class(class_def1):
            case tycon2:
                Class(class_def2):
                    return node_id_equal(class_def1.node_id, class_def2.node_id)
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

fn void_type() -> MyType:
    return new_type(TypeKind.Void())

fn bool_type() -> MyType:
    return new_type(TypeKind.Bool())

fn int_type() -> MyType:
    return new_type(TypeKind.Int())

fn float_type() -> MyType:
    return new_type(TypeKind.Float())

fn str_type() -> MyType:
    return new_type(TypeKind.Str())

fn undefined_type() -> MyType:
    return new_type(TypeKind.Undefined())

fn type_expression(expr: Expression) -> MyType:
    return new_type(TypeKind.TypeExpression(expr))

fn function_type(parameter_types: List[MyType], return_type: MyType) -> MyType:
    return new_type(TypeKind.Function(parameter_types, return_type))

fn type_parameter_ref(type_param: TypeParameter) -> MyType:
    return new_type(TypeKind.TypeParam(type_param))

fn new_type_var_ref(t_var: TypeVariable) -> MyType:
    return new_type(TypeKind.TypeVar(t_var))

fn new_type_var(unique: int) -> TypeVariable:
    let t_var = TypeVariable:
        unique: unique
        ty: Option.None()
    return t_var

fn type_var_equals(type_var1: TypeVariable, type_var2: TypeVariable) -> bool:
    return type_var1.unique == type_var2.unique

struct Module:
    name: str
    imports: List[Import]
    definitions: List[Definition]
    scope: Scope

fn new_module(name: str, imports: List[Import], definitions: List[Definition]) -> Module:
    let m = Module:
        name: name
        imports: imports
        definitions: definitions
        scope: Scope()
    return m

fn module_define_symbol(module: Module, definition: Definition):
    module.definitions.append(definition)
    case definition:
        Var(variable):
            module.scope.define(variable.variable.name, Symbol.Var(variable.variable))
        Function(func):
            module.scope.define(func.name, Symbol.Function(func))
        ExternFunction(efunc):
            module.scope.define(efunc.name, Symbol.ExternFunction(efunc))
        Enum(e):
            module.scope.define(e.name, Symbol.TypeConstructor(TyCon.Enum(e)))
        Struct(struct_def):
            module.scope.define(struct_def.node_id.name, Symbol.TypeConstructor(TyCon.Struct(struct_def)))
        Class(class_def):
            module.scope.define(class_def.node_id.name, Symbol.TypeConstructor(TyCon.Class(class_def)))

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
    Names(List[str])

struct ExternFunctionDef:
    name: str
    parameter_types: List[MyType]
    return_type: MyType

fn extern_function_type(func: ExternFunctionDef) -> MyType:
    return function_type(func.parameter_types, func.return_type)

class Scope:
    var symbols: Dictionary[Symbol] = Dictionary()

    fn define(name: str, symbol: Symbol):
        this.symbols.insert(name, symbol)
    
    fn is_defined(name: str) -> bool:
        # Check if given name is defined.
        case this.lookup(name):
            Some(s):
                return true
            None:
                return false

    fn lookup(name: str) -> Option[Symbol]:
        return this.symbols.get(name)

enum Symbol:
    Mod(Module)
    Function(FunctionDef)
    ExternFunction(ExternFunctionDef)
    Parameter(ParameterDef)
    Var(Variable)
    TypeConstructor(TyCon)
    Type(MyType)
    Variant(EnumVariant)
    Field(StructField)

fn symbol_to_str(symbol: Symbol) -> str:
    case symbol:
        Mod(m):
            return "mod:{m.name}"
        Function(f):
            return "function:{f.name}"
        ExternFunction(f):
            return "extern-function:{f.name}"
        Parameter(p):
            return "parameter:{p.name}"
        Var(v):
            return "var:{v.name}"
        TypeConstructor(v):
            return "tycon"
        Type(t):
            return "typ"
        Variant(v):
            return "EnumVariant({v.name})"
        Field(f):
            return "Field({f.name})"

enum Definition:
    Function(FunctionDef)
    ExternFunction(ExternFunctionDef)
    Enum(EnumDef)
    Struct(StructDef)
    Class(ClassDef)
    Var(VarDef)

struct VarDef:
    variable: Variable
    
fn type_parameter(name: str, id: int, location: Location) -> TypeParameter:
    let tp = TypeParameter:
        node_id: new_node_id(name, id)
        location: location
    return tp

struct TypeParameter:
    node_id: NodeId
    location: Location

fn struct_def(name: str, id: int, type_parameters: List[TypeParameter], fields: List[StructField], location: Location) -> StructDef:
    let s = StructDef:
        node_id: new_node_id(name, id)
        type_parameters: type_parameters
        fields: fields
        location: location
        scope: Scope()
    return s

struct StructDef:
    node_id: NodeId
    type_parameters: List[TypeParameter]
    fields: List[StructField]
    location: Location
    scope: Scope

fn new_struct_field(name: str, ty: MyType, location: Location) -> StructField:
    let f = StructField:
        name: name
        ty: ty
        location: location
    return f

struct StructField:
    name: str
    ty: MyType
    location: Location

fn enum_def(name: str, location: Location, type_parameters: List[TypeParameter], variants: List[EnumVariant]) -> EnumDef:
    let e = EnumDef:
        name: name
        location: location
        type_parameters: type_parameters
        variants: variants
        scope: Scope()
    return e

struct EnumDef:
    name: str
    location: Location
    type_parameters: List[TypeParameter]
    variants: List[EnumVariant]
    scope: Scope

struct EnumVariant:
    name: str
    location: Location
    payload: List[MyType]

struct ClassDef:
    node_id: NodeId
    location: Location
    type_parameters: List[TypeParameter]
    this_var: Variable
    definitions: List[Definition]
    scope: Scope

fn function_def(name: str, type_parameters: List[TypeParameter], parameters: List[ParameterDef], return_type: MyType, except_type: MyType, body: Statement, location: Location) -> FunctionDef:
    let f = FunctionDef:
        name: name
        is_pub: true
        type_parameters: type_parameters
        parameters: parameters
        return_type: return_type
        except_type: except_type
        location: location
        scope: Scope()
        body: body
    return f

struct FunctionDef:
    name: str
    is_pub: bool
    type_parameters: List[TypeParameter]
    parameters: List[ParameterDef]
    return_type: MyType
    except_type: MyType
    scope: Scope
    body: Statement
    location: Location

fn get_function_type(func: FunctionDef) -> MyType:
    let m: Dictionary[MyType] = Dictionary()
    let unique_id = 1
    for tp in func.type_parameters:
        let t_var = new_type_var(unique_id)
        m.insert(tp.node_id.name, new_type_var_ref(t_var))
        unique_id += 1
    let parameter_types: List[MyType] = List()
    for p in func.parameters:
        parameter_types.append(subst(p.ty, m))
    return function_type(parameter_types, subst(func.return_type, m))

fn parameter_def(name: str, ty: MyType, location: Location) -> ParameterDef:
    let p = ParameterDef:
        name: name
        ty: ty
        location: location
    return p

struct ParameterDef:
    name: str
    ty: MyType
    location: Location

fn variable(name: str, ty: MyType) -> Variable:
    let v = Variable:
        name: name
        ty: ty
    return v

struct Variable:
    name: str
    ty: MyType

fn statement(kind: StatementKind, location: Location) -> Statement:
    let statement = Statement:
        kind: kind
        location: location
    return statement

struct Statement:
    location: Location
    kind: StatementKind

enum StatementKind:
    If(IfStatement)
    While(WhileStatement)
    Loop(LoopStatement)
    For(ForStatement)
    Case(CaseStatement)
    Switch(SwitchStatement)
    Let(LetStatement)
    Try(TryStatement)
    Compound(List[Statement])
    Expr(Expression)
    Assignment(Expression, Option[BinaryOperator], Expression)
    Return(Option[Expression])
    Raise(Expression)
    Pass
    Break
    Continue

fn if_statement(condition: Expression, body: Statement, false_body: Statement, location: Location) -> Statement:
    let i = IfStatement:
        condition: condition
        true_body: body
        false_body: false_body

    let kind = StatementKind::If(i)
    return statement(kind, location)

struct IfStatement:
    condition: Expression
    true_body: Statement
    false_body: Statement

struct WhileStatement:
    condition: Expression
    body: Statement

fn while_statement(condition: Expression, body: Statement, location: Location) -> Statement:
    let w = WhileStatement:
        condition: condition
        body: body

    let kind = StatementKind::While(w)
    return statement(kind, location)

fn loop_statement(body: Statement, location: Location) -> Statement:
    let i = LoopStatement:
        body: body

    let kind = StatementKind::Loop(i)
    return statement(kind, location)

struct LoopStatement:
    body: Statement

fn for_statement(iter_var: str, iter_value: Expression, body: Statement, location: Location) -> Statement:
    let v = variable(iter_var, undefined_type())
    let f = ForStatement:
        iter_var: v
        iter_value: iter_value
        body: body
    return statement(StatementKind::For(f), location)

struct ForStatement:
    iter_var: Variable
    iter_value: Expression
    body: Statement

fn try_statement(try_body: Statement, except_param: ParameterDef, except_body: Statement, location: Location) -> Statement:
    let t = TryStatement:
        try_body: try_body
        except_param: except_param
        except_body: except_body
    return statement(StatementKind.Try(t), location)

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

struct SwitchStatement:
    value: Expression
    arms: List[SwitchArm]
    default_body: Statement

struct SwitchArm:
    location: Location
    value: Expression
    body: Statement

fn let_statement(variable: Variable, type_hint: Option[MyType], value: Expression, location: Location) -> Statement:
    let let_statement = LetStatement:
        variable: variable
        type_hint: type_hint
        value: value
    let kind = StatementKind.Let(let_statement)
    return statement(kind, location)

struct LetStatement:
    variable: Variable
    type_hint: Option[MyType]
    value: Expression

fn compound(inner: List[Statement], location: Location) -> Statement:
    if inner.len() == 1:
        return inner.get(0)
    else:
        let kind = StatementKind::Compound(inner)
        return statement(kind, location)

fn expression_statement(expr: Expression) -> Statement:
    let kind = StatementKind.Expr(expr)
    return statement(kind, expr.location)

fn assignment_statement(target: Expression, op: Option[BinaryOperator], value: Expression, location: Location) -> Statement:
    let kind = StatementKind.Assignment(target, op, value)
    return statement(kind, location)

fn return_statement(value: Option[Expression], location: Location) -> Statement:
    return statement(StatementKind.Return(value), location)

fn raise_statement(value: Expression, location: Location) -> Statement:
    return statement(StatementKind.Raise(value), location)

fn pass_statement(location: Location) -> Statement:
    return statement(StatementKind::Pass(), location)

struct Expression:
    location: Location
    ty: MyType
    kind: ExpressionKind

fn expression(kind: ExpressionKind, ty: MyType, location: Location) -> Expression:
    let expression = Expression:
        kind: kind
        ty: ty
        location: location
    return expression

enum ExpressionKind:
    Call(FunctionCall)
    GetAttr(Expression,str)
    GetIndex(Expression,List[Expression])
    Binop(BinopExpression)
    Unop(UnaryOperator, Expression)
    NameRef(str)
    VarRef(Variable)
    LoadSymbol(Symbol)
    IntLiteral(int)
    FloatLiteral(float)
    StringLiteral(str)
    BoolLiteral(bool)
    StructLiteral(MyType,List[Expression])
    ClassLiteral(MyType)
    ObjInit(MyType,List[FieldInit])
    Type(MyType)
    TypeConstructor(TyCon)
    Variant(MyType, EnumVariant)
    EnumLiteral(MyType, EnumVariant, List[Expression])
    Undefined

struct FieldInit:
    location: Location
    name: str
    value: Expression

fn call(callee: Expression, arguments: List[Expression], ty: MyType, location: Location) -> Expression:
    let c = FunctionCall:
        callee: callee
        arguments: arguments
    let kind = ExpressionKind::Call(c)
    return expression(kind, ty, location)

fn get_attr(base: Expression, field: str, ty: MyType, location: Location) -> Expression:
    let kind = ExpressionKind::GetAttr(base, field)
    return expression(kind, ty, location)

struct FunctionCall:
    callee: Expression
    arguments: List[Expression]

fn subscript(base: Expression, indici: List[Expression], ty: MyType, location: Location) -> Expression:
    let kind = ExpressionKind::GetIndex(base, indici)
    return expression(kind, ty, location)

# Reference a variable:
fn var_ref(v: Variable, location: Location) -> Expression:
    let kind = ExpressionKind::VarRef(v)
    return expression(kind, v.ty, location)

# Reference a symbol:
fn name_ref(name: str, location: Location) -> Expression:
    let kind = ExpressionKind::NameRef(name)
    let ty = undefined_type()
    return expression(kind, ty, location)

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

fn binop(lhs: Expression, op: BinaryOperator, rhs: Expression, ty: MyType, location: Location) -> Expression:
    let b = BinopExpression:
        lhs: lhs
        op: op
        rhs: rhs
    let kind = ExpressionKind::Binop(b)
    return expression(kind, ty, location)

enum UnaryOperator:
    Not
    Minus

fn unop(op: UnaryOperator, value: Expression, ty: MyType, location: Location) -> Expression:
    let kind = ExpressionKind::Unop(op, value)
    return expression(kind, ty, location)

fn bool_literal(value: bool, location: Location) -> Expression:
    let kind = ExpressionKind::BoolLiteral(value)
    let ty = bool_type()
    return expression(kind, ty, location)

fn integer_literal(value: int, location: Location) -> Expression:
    let kind = ExpressionKind::IntLiteral(value)
    let ty = int_type()
    return expression(kind, ty, location)

fn float_literal(value: float, location: Location) -> Expression:
    let kind = ExpressionKind::FloatLiteral(value)
    let ty = float_type()
    return expression(kind, ty, location)

fn string_literal(value: str, location: Location) -> Expression:
    let kind = ExpressionKind::StringLiteral(value)
    let ty = str_type()
    return expression(kind, ty, location)

fn undefined_value() -> Expression:
    return expression(ExpressionKind::Undefined(), undefined_type(), new_location(1, 1))

fn print_ast(mod: Module):
    print("Module: " + mod.name)
    let printer = AstPrinter()
    printer.indent()
    for imp in mod.imports:
        case imp.kind:
            Self:
                printer.print2("import {imp.modname}")
            Names(names):
                printer.print2("from {imp.modname} import ..")
    let vis = Visitor:
        data: printer
        on_definition: print_ast_definition
        on_type: print_ast_type
        on_statement: print_ast_statement
        on_expression: print_ast_expression
        on_node: print_ast_node
        
    visit_module(vis, mod)
    printer.dedent()

class AstPrinter:
    var indent_level: int = 0

    fn indent():
        this.indent_level += 3

    fn dedent():
        this.indent_level -= 3
    
    fn get_prefix() -> str:
        let space = ""
        let i = 0
        while i < this.indent_level:
            i += 1
            space = space + " "
        return space
    
    fn print2(txt: str):
        let prefix = this.get_prefix()
        print(prefix + txt)

fn print_ast_definition(printer: AstPrinter, definition: Definition, phase: VisitPhase):
    case phase:
        Pre:
            case definition:
                Function(func):
                    printer.print2("Func: {func.name}")
                ExternFunction(efunc):
                    printer.print2("Extern func: {efunc.name}")
                Struct(struct_def):
                    printer.print2("Struct: {struct_def.node_id.name},{struct_def.node_id.id}")
                Enum(e):
                    printer.print2("Enum: {e.name}")
                Class(class_def):
                    printer.print2("Class: {class_def.node_id.name},{class_def.node_id.id}")
                Var(v):
                    printer.print2("Var: {v.variable.name}")
            printer.indent()
        Post:
            printer.dedent()
    else:
        pass

fn print_ast_type(printer: AstPrinter, ty: MyType, phase: VisitPhase):
    case phase:
        Pre:
            let txt = type_to_string(ty)
            printer.print2("TYPE {txt}")
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
            printer.print2("STMT {txt}")
            printer.indent()
        Post:
            printer.dedent()
    else:
        pass

fn expression_to_string(expr: Expression) -> str:
    let txt = "?"
    case expr.kind:
        StringLiteral(val):
            txt = "String={val}"
        IntLiteral(val):
            txt = "Integer={val}"
        FloatLiteral(val):
            # TODO: float to str
            txt = "Float=..."
        BoolLiteral(val):
            if val:
                txt = "Bool(true)"
            else:
                txt = "Bool(false)"
        Call(c):
            txt = "CALL"
        NameRef(name):
            txt = "REF({name})"
        LoadSymbol(s):
            txt = "LOAD_SYM({symbol_to_str(s)})"
        GetAttr(base, attr):
            txt = "GET-ATTR({attr})"
        GetIndex(base, indici):
            txt = "GET-INDEX"
        Undefined:
            txt = "UNDEFINED"
        Binop(op):
            let op_txt = binary_op_to_str(op.op)
            txt = "BINOP({op_txt})"
        Unop(op, value):
            let op_txt = unary_op_to_str(op)
            txt = "UNOP({op_txt})"
        VarRef(v):
            txt = "VAR-REF({v.name})"
        ObjInit(ty, fields):
            txt = "OBJ-INIT"
        StructLiteral(ty, values):
            txt = "STRUCT-LITERAL"
        ClassLiteral(ty):
            txt = "CLASS-LITERAL"
        Type(ty):
            txt = "TYPE"
        TypeConstructor(tycon):
            txt = "TYPE-CONSTRUCTOR"
        Variant(ty, v):
            txt = "VARIANT"
        EnumLiteral(ty, v, values):
            txt = "ENUM-LITERAL"
    return txt

fn print_ast_expression(printer: AstPrinter, expr: Expression, phase: VisitPhase):
    case phase:
        Pre:
            printer.print2("EXPR {expression_to_string(expr)}")
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
    on_type: fn(D, MyType, VisitPhase)
    on_statement: fn(D, Statement, VisitPhase)
    on_expression: fn(D, Expression, VisitPhase)
    on_node: fn(D, VisitNode, VisitPhase)

enum VisitPhase:
    Pre
    Mid
    Post

enum VisitNode:
    Arm(CaseArm)

fn visit_module[T](visitor: Visitor[T], mod: Module):
    for definition in mod.definitions:
        visit_definition(visitor, definition)



fn visit_definition[T](visitor: Visitor[T], definition: Definition):
    visitor.on_definition(visitor.data, definition, VisitPhase.Pre())
    case definition:
        Function(func):
            # print("VISIT {func.name}")
            for parameter in func.parameters:
                visit_type(visitor, parameter.ty)
            visit_type(visitor, func.return_type)
            visit_statement(visitor, func.body)
        ExternFunction(e):
            pass
        Enum(e):
            for variant in e.variants:
                for p in variant.payload:
                    visit_type(visitor, p)

        Struct(s):
            for field in s.fields:
                visit_type(visitor, field.ty)
        Class(c):
            for d2 in c.definitions:
                visit_definition(visitor, d2)
        Var(v):
            visit_type(visitor, v.variable.ty)
    visitor.on_definition(visitor.data, definition, VisitPhase.Post())

fn visit_type[T](visitor: Visitor[T], ty: MyType):
    # print("Visit type")
    visitor.on_type(visitor.data, ty, VisitPhase.Pre())
    case ty.kind:
        TypeExpression(expr):
            visit_expression(visitor, expr)
        App(tycon, type_arguments):
            for type_argument in type_arguments:
                visit_type(visitor, type_argument)
        Function(parameter_types, return_type):
            for parameter_type in parameter_types:
                visit_type(visitor, parameter_type)
            visit_type(visitor, return_type)
    else:
        pass
    visitor.on_type(visitor.data, ty, VisitPhase.Post())

fn visit_statement[T](visitor: Visitor[T], statement: Statement):
    visitor.on_statement(visitor.data, statement, VisitPhase.Pre())
    case statement.kind:
        Pass:
            pass
        Let(let_statement):
            case let_statement.type_hint:
                Some(t):
                    visit_type(visitor, t)
                None:
                    pass
            visit_expression(visitor, let_statement.value)
        If(if_statement):
            visit_expression(visitor, if_statement.condition)
            visit_statement(visitor, if_statement.true_body)
            visit_statement(visitor, if_statement.false_body)
        While(while_statement):
            visit_expression(visitor, while_statement.condition)
            visit_statement(visitor, while_statement.body)
        Loop(loop_statement):
            visit_statement(visitor, loop_statement.body)
        Switch(switch_statement):
            visit_expression(visitor, switch_statement.value)
            # TODO: visit arms!
        For(for_statement):
            visit_expression(visitor, for_statement.iter_value)
            visitor.on_statement(visitor.data, statement, VisitPhase.Mid())
            visit_statement(visitor, for_statement.body)
        Try(try_statement):
            visit_statement(visitor, try_statement.try_body)
            visit_type(visitor, try_statement.except_param.ty)
            visit_statement(visitor, try_statement.except_body)
        Case(case_statement):
            visit_expression(visitor, case_statement.value)
            visitor.on_statement(visitor.data, statement, VisitPhase.Mid())
            for arm in case_statement.arms:
                let arm_node = VisitNode.Arm(arm)
                visitor.on_node(visitor.data, arm_node, VisitPhase.Pre())
                visit_statement(visitor, arm.body)
                visitor.on_node(visitor.data, arm_node, VisitPhase.Post())
        Compound(inner):
            for s in inner:
                visit_statement(visitor, s)
        Expr(expr):
            visit_expression(visitor, expr)
        Assignment(target, op, expr):
            visit_expression(visitor, target)
            visit_expression(visitor, expr)
        Return(opt_val):
            case opt_val:
                Some(expr):
                    visit_expression(visitor, expr)
                None:
                    pass
        Raise(exc_val):
            visit_expression(visitor, exc_val)
        Break:
            pass
        Continue:
            pass
    visitor.on_statement(visitor.data, statement, VisitPhase.Post())

fn visit_expression[T](visitor: Visitor[T], expression: Expression):
    visitor.on_expression(visitor.data, expression, VisitPhase.Pre())

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
            visit_expression(visitor, v.callee)
            for arg in v.arguments:
                visit_expression(visitor, arg)
        GetAttr(base, index):
            visit_expression(visitor, base)
        GetIndex(base, indici):
            visit_expression(visitor, base)
            for arg in indici:
                visit_expression(visitor, arg)
        Binop(v):
            visit_expression(visitor, v.lhs)
            visit_expression(visitor, v.rhs)
        Unop(op,value):
            visit_expression(visitor, value)
        VarRef(v):
            pass
        ObjInit(ty, fields):
            visit_type(visitor, ty)
            for field in fields:
                visit_expression(visitor, field.value)
        StructLiteral(ty, values):
            visit_type(visitor, ty)
            for value in values:
                visit_expression(visitor, value)
        ClassLiteral(ty):
            visit_type(visitor, ty)
        Type(ty):
            visit_type(visitor, ty)
        TypeConstructor(tycon):
            pass
        Variant(ty, v):
            pass
        EnumLiteral(ty, v, values):
            for value in values:
                visit_expression(visitor, value)

    visitor.on_expression(visitor.data, expression, VisitPhase.Post())