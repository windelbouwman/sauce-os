
import std
from location import Location

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

struct Module:
    name: str
    # TODO: support list:
    # functions: list<Function>

struct FunctionDef:
    name: str
    is_pub: bool
    # TODO:
    # parameters: list<int>
    # body: list<Statement>

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

fn if_statement(condition: Expression, body: Statement, location: Location) -> Statement:
    let i = IfStatement:
        condition: condition
        body: body

    let kind = StatementKind::If(i)
    return statement(kind, location)

struct IfStatement:
    condition: Expression
    body: Statement

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
    Binop(BinopExpression)
    IntLiteral(int)
    # FloatLiteral(float)
    # StringLiteral(str)
    BoolLiteral(bool)

fn call(callee: Expression, ty: MyType, location: Location) -> Expression:
    let c = FunctionCall:
        callee: callee
        # TODO: arguments
    let kind = ExpressionKind::Call(c)
    return expression(kind, ty, location)

struct FunctionCall:
    callee: Expression
    # TODO:
    # arguments: list<Expression>

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

fn print_ast(mod: Module):
    std::print("Module: " + mod.name)
    #for func in mod.functions:
    #    std.print(func.name)

