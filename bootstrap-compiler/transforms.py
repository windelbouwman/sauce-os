""" Transform ast into a simpler ast.

Example transformations:
- turn each 'loop' into a 'while-true'
- turn for-loops into while loops
"""

import logging


from . import ast, types
logger = logging.getLogger('transforms')


class BaseTransformer(ast.AstVisitor):
    def transform(self, module: ast.Module):
        logger.info(f"Transforming")
        self.visit_module(module)


class LoopRewriter(BaseTransformer):
    def visit_statement(self, statement: ast.Statement):
        super().visit_statement(statement)
        kind = statement.kind

        if isinstance(kind, ast.LoopStatement):
            # Turn loop into a while-true clause
            yes_value = ast.bool_constant(True, statement.location)
            statement.kind = ast.WhileStatement(yes_value, kind.inner)
        elif isinstance(kind, ast.ForStatement):
            # Turn for loop into while loop.
            #
            # Turn this:
            # for v in arr:
            #   ...
            #
            # Into this:
            # i = 0
            # x = arr
            # while i < len(arr):
            #   v = x[i]
            #   ...
            #   i = i + 1

            assert isinstance(kind.values.ty.kind, types.ArrayType)
            # x = arr
            x_var = ast.Variable('x', kind.values.ty)
            let_x = ast.let_statement(
                x_var, None, kind.values, statement.location)

            # i = 0
            i_var = ast.Variable('i', types.int_type)
            zero = ast.numeric_constant(0, statement.location)
            let_i0 = ast.let_statement(
                i_var, None, zero, statement.location)

            # i < len(arr)
            array_size = ast.numeric_constant(
                kind.values.ty.kind.size, statement.location)
            loop_condition = i_var.ref_expr(
                statement.location).binop('<', array_size)

            # v = x[i]
            v_var: ast.Variable = kind.variable
            let_v = ast.let_statement(v_var, None, x_var.ref_expr(
                statement.location).array_index(i_var.ref_expr(statement.location)), statement.location)

            # i++
            one = ast.numeric_constant(1, statement.location)
            inc_i = ast.assignment_statement(i_var.ref_expr(
                statement.location), i_var.ref_expr(statement.location).binop('+', one), statement.location)

            loop_body = ast.compound_statement(
                [let_v, kind.inner, inc_i], kind.inner.location)
            while_loop = ast.while_statement(
                loop_condition, loop_body, statement.location)
            statements = [let_x, let_i0, while_loop]
            statement.kind = ast.CompoundStatement(statements)
