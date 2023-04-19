
from std import print
from location import Location, new_location
from datatypes import List, Option, Dictionary

# TODO: implement type-defs!
# type MyType = int
struct MyType:
    stub: int
    kind: TypeKind

fn new_type(kind: TypeKind) -> MyType:
    let t = MyType:
        stub: 0
        kind: kind
    return t

enum TypeKind:
    Undefined
    Bool
    Int
    Str
    Float
    TypeExpression(Expression)

fn bool_type() -> MyType:
    return new_type(TypeKind::Bool())

fn int_type() -> MyType:
    return new_type(TypeKind::Int())

fn float_type() -> MyType:
    return new_type(TypeKind::Float())

fn str_type() -> MyType:
    return new_type(TypeKind::Str())

fn undefined_type() -> MyType:
    return new_type(TypeKind::Undefined())

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
        Enum(e):
            module.scope.define(e.name, Symbol.Enum(e))
        Struct(s):
            module.scope.define(s.name, Symbol.Struct(s))
        Class(c):
            module.scope.define(c.name, Symbol.Class(c))

struct Import:
    modname: str
    location: Location

struct FromImport:
    modname: str
    location: Location
    names: List[str]

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
    Parameter(ParameterDef)
    Var(Variable)
    Struct(StructDef)
    Enum(EnumDef)
    Class(ClassDef)

enum Definition:
    Function(FunctionDef)
    Enum(EnumDef)
    Struct(StructDef)
    Class(ClassDef)
    Var(VarDef)

struct VarDef:
    variable: Variable
    
fn type_parameter(name: str, location: Location) -> TypeParameter:
    let tp = TypeParameter:
        name: name
        location: location
    return tp

struct TypeParameter:
    name: str
    location: Location

fn struct_def(name: str, fields: List[StructField], location: Location) -> StructDef:
    let s = StructDef:
        name: name
        fields: fields
        location: location
        scope: Scope()
    return s

struct StructDef:
    name: str
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

fn enum_def(name: str, location: Location, variants: List[EnumVariant]) -> EnumDef:
    let e = EnumDef:
        name: name
        location: location
        variants: variants
        scope: Scope()
    return e

struct EnumDef:
    name: str
    location: Location
    variants: List[EnumVariant]
    scope: Scope

struct EnumVariant:
    name: str
    location: Location

struct ClassDef:
    name: str
    location: Location
    scope: Scope

fn function_def(name: str, parameters: List[ParameterDef], body: Statement, location: Location) -> FunctionDef:
    let f = FunctionDef:
        name: name
        is_pub: true
        parameters: parameters
        location: location
        scope: Scope()
        body: body
    return f

struct FunctionDef:
    name: str
    is_pub: bool
    parameters: List[ParameterDef]
    scope: Scope
    body: Statement
    location: Location

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
    Compound(List[Statement])
    Expr(Expression)
    Assignment(Expression, Expression)
    Return(Option[Expression])
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
    let v = Variable:
        name: iter_var
        ty: undefined_type()
    let f = ForStatement:
        iter_var: v
        iter_value: iter_value
        body: body
    return statement(StatementKind::For(f), location)

struct ForStatement:
    iter_var: Variable
    iter_value: Expression
    body: Statement

struct CaseStatement:
    value: Expression
    arms: List[CaseArm]
    else_clause: Option[Statement]

struct CaseArm:
    body: Statement

struct SwitchStatement:
    value: Expression
    arms: List[SwitchArm]
    default_body: Statement

struct SwitchArm:
    location: Location
    value: Expression
    body: Statement

fn let_statement(variable: Variable, value: Expression, location: Location) -> Statement:
    let let2 = LetStatement:
        variable: variable
        value: value
    let kind = StatementKind::Let(let2)
    return statement(kind, location)

struct LetStatement:
    variable: Variable
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

fn assignment_statement(target: Expression, value: Expression, location: Location) -> Statement:
    let kind = StatementKind.Assignment(target, value)
    return statement(kind, location)

fn return_statement(value: Option[Expression], location: Location) -> Statement:
    return statement(StatementKind::Return(value), location)

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
    NameRef(str)
    VarRef(Variable)
    LoadSymbol(Symbol)
    IntLiteral(int)
    FloatLiteral(float)
    StringLiteral(str)
    BoolLiteral(bool)
    ObjInit(MyType,List[FieldInit])
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
    Add
    Sub
    Mul
    Div

fn binop(lhs: Expression, op: BinaryOperator, rhs: Expression, ty: MyType, location: Location) -> Expression:
    let b = BinopExpression:
        lhs: lhs
        op: op
        rhs: rhs
    let kind = ExpressionKind::Binop(b)
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
    let vis = Visitor:
        data: printer
        on_definition: print_ast_definition
        on_statement: print_ast_statement
        on_expression: print_ast_expression
    
    visit_module(vis, mod)

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

fn print_ast_definition(printer: AstPrinter, definition: Definition, is_pre: bool):
    if is_pre:
        case definition:
            Function(func):
                print("Func: {func.name}")
            Struct(s):
                print("Struct: {s.name}")
            Enum(e):
                print("Enum: {e.name}")
            Class(c):
                print("Class: {c.name}")
            Var(v):
                print("Var: {v.variable.name}")
        printer.indent()
    else:
        printer.dedent()

fn print_ast_statement(printer: AstPrinter, statement: Statement, is_pre: bool):
    if is_pre:
        let txt = "?"
        case statement.kind:
            Expr(x):
                txt = "EXPR"
            Assignment(target, expr):
                txt = "ASSIGN"
            If(x):
                txt = "IF"
            Return(x):
                txt = "RETURN"
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
            Case(f):
                txt = "CASE"
            Let(letty):
                txt = "LET"
            Switch(switchy):
                txt = "SWITCH"

        printer.print2("STMT {txt}")
        printer.indent()
    else:
        printer.dedent()

fn print_ast_expression(printer: AstPrinter, expr: Expression, is_pre: bool):
    if is_pre:
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
                txt = "LOAD_SYM"
            GetAttr(base, attr):
                txt = "GET-ATTR({attr})"
            GetIndex(base, indici):
                txt = "GET-INDEX"
            Undefined:
                txt = "UNDEFINED"
            Binop(op):
                let op_txt = binary_op_to_str(op.op)
                txt = "BINOP({op_txt})"
            VarRef(v):
                txt = "VAR-REF({v.name})"
            ObjInit(ty, fields):
                txt = "OBJ-INIT"
        
        printer.print2("EXPR {txt}")
        printer.indent()
    else:
        printer.dedent()

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
        Add:
            op_txt = "+"
        Sub:
            op_txt = "-"
        Mul:
            op_txt = "*"
        Div:
            op_txt = "/"
    return op_txt

struct Visitor[D]:
    data: D
    on_definition: fn(data: D, definition: Definition, is_pre: bool)
    on_statement: fn(data: D, statement: Statement, is_pre: bool)
    on_expression: fn(data: D, expression: Expression, is_pre: bool)

fn visit_module[T](visitor: Visitor[T], mod: Module):
    for definition in mod.definitions:
        visitor.on_definition(visitor.data, definition, true)
        case definition:
            Function(func):
                # print("VISIT {func.name}")
                visit_statement(visitor, func.body)
            Enum(e):
                pass
            Struct(s):
                pass
            Class(c):
                pass
            Var(v):
                pass
        visitor.on_definition(visitor.data, definition, false)

fn visit_statement[T](visitor: Visitor[T], statement: Statement):
    visitor.on_statement(visitor.data, statement, true)
    case statement.kind:
        Pass:
            pass
        Let(letty):
            visit_expression(visitor, letty.value)
        If(iffy):
            visit_expression(visitor, iffy.condition)
            visit_statement(visitor, iffy.true_body)
            visit_statement(visitor, iffy.false_body)
        While(whilly):
            visit_expression(visitor, whilly.condition)
            visit_statement(visitor, whilly.body)
        Loop(loopy):
            visit_statement(visitor, loopy.body)
        Switch(switchy):
            visit_expression(visitor, switchy.value)
            # TODO: visit arms!
        For(f):
            visit_expression(visitor, f.iter_value)
            visit_statement(visitor, f.body)
        Case(c):
            visit_expression(visitor, c.value)
            for arm in c.arms:
                visit_statement(visitor, arm.body)
        Compound(inner):
            for s in inner:
                visit_statement(visitor, s)
        Expr(expr):
            visit_expression(visitor, expr)
        Assignment(target, expr):
            visit_expression(visitor, target)
            visit_expression(visitor, expr)
        Return(opt_val):
            case opt_val:
                Some(expr):
                    visit_expression(visitor, expr)
                None:
                    pass
        Break:
            pass
        Continue:
            pass
    visitor.on_statement(visitor.data, statement, false)

fn visit_expression[T](visitor: Visitor[T], expression: Expression):
    visitor.on_expression(visitor.data, expression, true)

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
        VarRef(v):
            pass
        ObjInit(ty, fields):
            for field in fields:
                visit_expression(visitor, field.value)

    visitor.on_expression(visitor.data, expression, false)