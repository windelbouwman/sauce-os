""" Transform ast into a simpler ast.

Example transformations:
- turn each 'loop' into a 'while-true'
- turn for-loops into while loops
"""

import logging


from . import ast
logger = logging.getLogger('transforms')


def transform(modules: list[ast.Module]):
    """ Transform a slew of modules (in-place)

    Some real compilation being done here.
    """
    LoopRewriter().transform(modules)
    EnumRewriter().transform(modules)


class BaseTransformer(ast.AstVisitor):
    def transform(self, modules: list[ast.Module]):
        logger.info(f"Transforming")
        for module in modules:
            self.visit_module(module)


class LoopRewriter(BaseTransformer):
    def __init__(self):
        super().__init__()

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

            assert isinstance(kind.values.ty.kind, ast.ArrayType)
            # x = arr
            x_var = ast.Variable('x', kind.values.ty, statement.location)
            let_x = ast.let_statement(
                x_var, None, kind.values, statement.location)

            # i = 0
            i_var = ast.Variable('i', ast.int_type, statement.location)
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


class EnumRewriter(BaseTransformer):
    def __init__(self):
        super().__init__()
        self._tagged_unions = {}

    def visit_module(self, module: ast.Module):
        new_defs = []
        for definition in module.definitions:
            if isinstance(definition, ast.EnumDef):
                # Create tagged union types / definitions

                builder2 = ast.StructBuilder(
                    f'{definition.name}Data', True, definition.location)
                for variant in definition.variants:
                    if len(variant.payload) == 0:
                        t3 = ast.int_type
                    elif len(variant.payload) == 1:
                        t3 = variant.payload[0]
                    else:
                        assert len(variant.payload) > 1
                        builder3 = ast.StructBuilder(
                            f'{definition.name}{variant.name}Data', False, variant.location)
                        for nr, p in enumerate(variant.payload):
                            builder3.add_field(f'f_{nr}', p, variant.location)
                        s_def3 = builder3.finish()
                        new_defs.append(s_def3)
                        t3 = s_def3.get_type([])

                    builder2.add_field(
                        f"{variant.name}", t3, variant.location)
                union_def = builder2.finish()
                new_defs.append(union_def)
                builder1 = ast.StructBuilder(
                    f'{definition.name}', False, definition.location)
                builder1.add_field('tag', ast.int_type, definition.location)
                builder1.add_field(
                    'data', union_def.get_type([]), definition.location)
                tagged_union_def = builder1.finish()
                new_defs.append(tagged_union_def)
                self._tagged_unions[id(definition)
                                    ] = tagged_union_def.get_type([])

        module.definitions += new_defs
        super().visit_module(module)

    def visit_type(self, ty: ast.MyType):
        super().visit_type(ty)
        kind = ty.kind
        if ty.is_enum():
            ty.kind = self._tagged_unions[id(kind.enum_def)].kind

    def visit_statement(self, statement: ast.Statement):
        """
        Rewrite case statement over an enum type.
        - Change case into switch statement over an integer tag.
        - Change arm variables into seperate let statements
        - Grab values from arm out of the tagged union
        """
        super().visit_statement(statement)
        kind = statement.kind

        if isinstance(kind, ast.CaseStatement):
            # x = value
            x_var = ast.Variable('_x1337', kind.value.ty, statement.location)
            let_x = ast.let_statement(
                x_var, None, kind.value, statement.location)

            arms = []
            for arm in kind.arms:
                variant_idx: int = arm.variant.index

                # assign variables:
                body = []
                if len(arm.variables) == 0:
                    pass
                elif len(arm.variables) == 1:
                    union_val = x_var.ref_expr(
                        arm.location).get_attr(1).get_attr(variant_idx)
                    let_v = ast.let_statement(
                        arm.variables[0], None, union_val, arm.location)
                    body.append(let_v)
                else:

                    for var_idx, var in enumerate(arm.variables):
                        union_val = x_var.ref_expr(
                            arm.location).get_attr(1).get_attr(variant_idx)
                        val2 = union_val.get_attr(var_idx)
                        let_v = ast.let_statement(
                            var, None, val2, arm.location)
                        body.append(let_v)
                body.append(arm.body)
                body = ast.compound_statement(body, arm.location)
                tag_val = ast.numeric_constant(variant_idx, arm.location)
                arms.append(ast.SwitchArm(tag_val, body, arm.location))
            default_body = ast.pass_statement(statement.location)

            # switch x.tag
            switch_1 = ast.switch_statement(
                x_var.ref_expr(statement.location).get_attr(0), arms, default_body, statement.location)
            statement.kind = ast.CompoundStatement([let_x, switch_1])

    def visit_expression(self, expression: ast.Expression):
        """ Rewrite enum literal into tagged union
        """
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, ast.EnumLiteral):

            tag_value = ast.numeric_constant(
                kind.variant.index, expression.location)
            tagged_union_ty: ast.MyType = self._tagged_unions[id(
                kind.enum_def)]
            union_ty = tagged_union_ty.get_field_type(1)

            if len(kind.values) == 0:
                # Dummy value
                v = ast.numeric_constant(0, expression.location)
            elif len(kind.values) == 1:
                v = kind.values[0]
            else:
                assert len(kind.values) > 1
                t = union_ty.get_field_type(kind.variant.index)
                v = ast.struct_literal(t, kind.values, expression.location)
            union_value = ast.union_literal(
                union_ty, kind.variant.index, v, expression.location)

            expression.kind = ast.StructLiteral(
                tagged_union_ty, [tag_value, union_value])
