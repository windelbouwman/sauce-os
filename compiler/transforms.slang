
# from ast import Statement
import ast

fn transform_statement(statement: ast.Statement):
    case statement.kind:
        Loop(x):
            let condition = ast.bool_literal(true, statement.location)
            let w = ast.WhileStatement:
                condition: condition
                body: x.body
            statement.kind = ast.StatementKind.While(w)
    else:
        pass

