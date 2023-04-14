
from ast import Statement
import ast

fn transform_statement(statement: Statement):
    case statement.kind:
        Loop(x):
            let condition = ast.bool_literal(true, statement.location)
            let w = ast.WhileStatement:
                condition: condition
                body: x.body
            statement.kind = ast.StatementKind.While(w)
    else:
        pass


fn transform_switch(statement: ast.Statement):
    # Turn switch into sequence of if-else
    case statement.kind:
        Switch(s):
            # TODO:
            let ty = ast.bool_type()

            let x_var = ast.variable("x", ty)
            let let_x = ast.let_statement(x_var, s.value, statement.location)

            let else_clause = s.default_body
            for arm in s.arms:
                let x_ref = ast.var_ref(x_var, statement.location)
                let eq_op = ast.BinaryOperator.Equals()
                let condition = ast.binop(x_ref, eq_op, arm.value, ty, statement.location)

                else_clause = ast.if_statement(condition, arm.body, else_clause, arm.location)
            
            statement.kind = let_x.kind
    else:
        pass
