
import std
from location import Location

struct Module:
    name: str
    # TODO: support list:
    # functions: list<Function>

struct Function:
    name: str
    is_pub: bool
    # TODO:
    # parameters: list<int>
    # body: list<Statement>

struct Statement:
    location: Location
    kind: StatementKind

enum StatementKind:
    If(If)
    While(While)
    Loop(Loop)

struct If:
    location: Location
    condition: Expression
    body: Statement

struct While:
    location: Location
    condition: Expression
    body: Statement

struct Loop:
    location: Location
    body: Statement

struct Expression:
    location: Location
    ty: int
    kind: ExpressionKind

enum ExpressionKind:
    Call(Call)

struct Call:
    location: Location
    callee: Expression
    # arguments: list<Expression>

fn print_ast(mod: Module):
    std::print("Module: " + mod.name)
    #for func in mod.functions:
    #    std.print(func.name)

