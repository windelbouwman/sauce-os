
import std
from location import Location, new_location
from datatypes import List, Option

# TODO: implement type-defs!
# type MyType = int
struct MyType:
    stub: int

fn bool_type() -> MyType:
    # TODO
    let t = MyType:
        stub: 0
    return t

fn int_type() -> MyType:
    # TODO
    return bool_type()

fn str_type() -> MyType:
    # TODO
    return bool_type()

fn undefined_type() -> MyType:
    # TODO
    return bool_type()

struct Module:
    name: str
    definitions: List[Definition]

enum Definition:
    Function(FunctionDef)

fn function_def(name: str, body: Statement, location: Location) -> FunctionDef:
    let f = FunctionDef:
        name: name
        is_pub: true
        body: body
    return f

struct FunctionDef:
    name: str
    is_pub: bool
    # TODO:
    # parameters: list<int>
    body: Statement

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
    Switch(SwitchStatement)
    Let(LetStatement)
    Compound(List[Statement])
    Expr(Expression)
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
    let kind = StatementKind::Compound(inner)
    return statement(kind, location)

fn expression_statement(expr: Expression) -> Statement:
    let kind = StatementKind::Expr(expr)
    return statement(kind, expr.location)

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
    Binop(BinopExpression)
    NameRef(str)
    VarRef(Variable)
    IntLiteral(int)
    # FloatLiteral(float)
    StringLiteral(str)
    BoolLiteral(bool)
    Undefined

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
    op: str
    rhs: Expression

fn binop(lhs: Expression, op: str, rhs: Expression, ty: MyType, location: Location) -> Expression:
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

fn string_literal(value: str, location: Location) -> Expression:
    let kind = ExpressionKind::StringLiteral(value)
    let ty = str_type()
    return expression(kind, ty, location)

fn undefined_value() -> Expression:
    return expression(ExpressionKind::Undefined(), undefined_type(), new_location(1, 1))

fn print_ast(mod: Module):
    std::print("Module: " + mod.name)
    #for func in mod.functions:
    #    std.print(func.name)

fn print_expr(expr: Expression):
    let txt = "?"
    case expr.kind:
        StringLiteral(val):
            txt = "String={val}"
    else:
        txt = "??"
    
    std.print("EXPR {txt}")