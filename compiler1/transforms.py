"""Transform ast into a simpler ast.

Example transformations:
- turn each 'loop' into a 'while-true'
- turn for-loops into while loops
"""

import logging
from dataclasses import dataclass
from . import ast
from .location import Location, Span

logger = logging.getLogger("transforms")


class BaseTransformer(ast.AstVisitor):
    name = "?"

    def __init__(self, id_context: ast.IdContext):
        super().__init__()
        self._id_context = id_context

    def transform(self, modules: list[ast.Module]):
        logger.info(f"Transforming {self.name}")
        for module in modules:
            self.visit_module(module)

    def new_variable(self, name: str, ty: ast.Type, location: Location) -> ast.Variable:
        id = self.new_id(name)
        return ast.Variable(id, ty, location)

    def new_id(self, name: str) -> ast.Id:
        return self._id_context.new_id(name)


def rewrite_loops(id_context: ast.IdContext, rt_module: ast.Module, modules):
    LoopRewriter(id_context, rt_module).transform(modules)


class LoopRewriter(BaseTransformer):
    name = "loop-rewrite"

    def __init__(self, id_context: ast.IdContext, rt_module: ast.Module):
        super().__init__(id_context)

        self._rt_module = rt_module

    def visit_statement(self, statement: ast.Statement):
        super().visit_statement(statement)
        kind = statement.kind

        if isinstance(kind, ast.LoopStatement):
            # Turn loop into a while-true clause
            yes_value = ast.bool_constant(True, statement.location)
            statement.kind = ast.WhileStatement(yes_value, kind.block)
        elif isinstance(kind, ast.ForStatement):
            if kind.values.ty.is_array():
                statement.kind = self.rewrite_loop_over_array(kind, statement.location)
            elif kind.values.ty.is_iterable_like():
                statement.kind = self.rewrite_loop_over_iterator(
                    kind, statement.location
                )
            elif kind.values.ty.is_sequence_like():
                statement.kind = self.rewrite_loop_over_sequence(
                    kind, statement.location
                )
            else:
                raise RuntimeError(f"Invalid for loop type: {kind.values.ty}")

    def rewrite_loop_over_array(
        self, kind: ast.ForStatement, location: Location
    ) -> ast.CompoundStatement:
        """
        Turn for loop into while loop.

        Turn this:
        # for v in arr:
        #   ...
        #
        Into this:
        # i = 0
        # x = arr
        # while i < len(arr):
        #   v = x[i]
        #   ...
        #   i = i + 1
        """

        # x = arr
        x_var = self.new_variable("x", kind.values.ty, location)
        let_x = ast.let_statement(x_var, None, kind.values, location)

        # i = 0
        i_var = self.new_variable("i", ast.int_type, location)
        zero = ast.numeric_constant(0, location)
        let_i0 = ast.let_statement(i_var, None, zero, location)

        # i < len(arr)
        array_size = ast.numeric_constant(kind.values.ty.kind.size, location)
        loop_condition = i_var.ref_expr(location).binop("<", array_size)

        # v = x[i]
        v_var: ast.Variable = kind.variable
        let_v = ast.let_statement(
            v_var,
            None,
            x_var.ref_expr(location).array_index(i_var.ref_expr(location)),
            location,
        )

        # i += 1
        one = ast.numeric_constant(1, location)
        inc_i = ast.assignment_statement(
            i_var.ref_expr(location),
            "+=",
            one,
            location,
        )

        loop_body = ast.compound_statement(
            [let_v, inc_i, kind.block.body], kind.block.body.location
        )
        loop_block = ast.ScopedBlock(loop_body)
        while_loop = ast.while_statement(loop_condition, loop_block, location)
        statements = [let_x, let_i0, while_loop]
        return ast.CompoundStatement(statements)

    def rewrite_loop_over_iterator(
        self, kind: ast.ForStatement, location: Location
    ) -> ast.CompoundStatement:
        # Try to rewrite using iterator.

        # Turn this:
        # for e in x:
        #     print("Item[{n}]= {e.value}")
        #     n = n + 1

        # Into this:
        # let it = x.iter()
        # loop:
        #     let opt = it.next()
        #     case opt:
        #         None:
        #             break
        #         Some(element):
        #             print("Item[{n}]=" + std::int_to_str(element.value))

        iter_ty: ast.Type = kind.values.ty.get_field_type("iter").kind.return_type
        opt_ty: ast.Type = iter_ty.get_field_type("next").kind.return_type

        it_var = self.new_variable("it", iter_ty, location)
        opt_var = self.new_variable("opt", opt_ty, location)
        let_it_var = ast.let_statement(
            it_var, None, kind.values.call_method("iter", []), location
        )
        let_opt_var = ast.let_statement(
            opt_var,
            None,
            it_var.ref_expr(location).call_method("next", []),
            location,
        )
        beak_block = break_block = ast.ScopedBlock(ast.break_statement(location))
        none_arm = ast.CaseArm("None", [], break_block, location)
        some_arm = ast.CaseArm("Some", [kind.variable], kind.block, location)
        arms = [none_arm, some_arm]
        case_statement = ast.case_statement(
            opt_var.ref_expr(location), arms, None, location
        )
        yes_value = ast.bool_constant(True, location)
        loop_body = ast.compound_statement([let_opt_var, case_statement], location)
        loop_block = ast.ScopedBlock(loop_body)
        loop_statement = ast.while_statement(yes_value, loop_block, location)
        return ast.CompoundStatement([let_it_var, loop_statement])

    def rewrite_loop_over_sequence(
        self, kind: ast.ForStatement, location: Location
    ) -> ast.CompoundStatement:
        # x = arr
        x_var = self.new_variable("x", kind.values.ty, location)
        let_x = ast.let_statement(x_var, None, kind.values, location)

        # index = 0
        index_var = self.new_variable("index", ast.int_type, location)
        zero = ast.numeric_constant(0, location)
        let_index = ast.let_statement(index_var, None, zero, location)

        # size = x.len()
        size_var = self.new_variable("size", ast.int_type, location)
        x_len = x_var.ref_expr(location).call_method("len", [])
        let_size = ast.let_statement(size_var, None, x_len, location)

        # index < size
        loop_condition = index_var.ref_expr(location).binop(
            "<", size_var.ref_expr(location)
        )

        # v = x.get(index)
        arguments = [
            ast.LabeledExpression("index", index_var.ref_expr(location), location)
        ]

        let_v = ast.let_statement(
            kind.variable,
            None,
            x_var.ref_expr(location).call_method("get", arguments),
            location,
        )

        # index += 1
        one = ast.numeric_constant(1, location)
        inc_index = ast.assignment_statement(
            index_var.ref_expr(location),
            "+=",
            one,
            location,
        )

        loop_body = ast.compound_statement(
            [let_v, inc_index, kind.block.body], kind.block.body.location
        )
        loop_block = ast.ScopedBlock(loop_body)
        while_loop = ast.while_statement(loop_condition, loop_block, location)

        return ast.CompoundStatement([let_x, let_index, let_size, while_loop])

    def visit_expression(self, expression: ast.Expression):
        """Rewrite To-String operator"""
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, ast.ToString):
            if kind.expr.ty.is_str():
                # Simple, we are done!
                expression.kind = kind.expr.kind
            elif kind.expr.ty.is_int():
                # call built-in int_to_str
                int_to_str = self.get_rt_function("int_to_str")
                callee = ast.obj_ref(int_to_str, ast.void_type, expression.location)
                args = [ast.LabeledExpression("value", kind.expr, kind.expr.location)]
                expression.kind = ast.FunctionCall(callee, args)
            elif kind.expr.ty.is_char():
                # call built-in char_to_str
                char_to_str = self.get_rt_function("char_to_str")
                callee = ast.obj_ref(char_to_str, ast.void_type, expression.location)
                args = [ast.LabeledExpression("value", kind.expr, kind.expr.location)]
                expression.kind = ast.FunctionCall(callee, args)
            elif kind.expr.ty.has_field("to_string"):
                # Invoke to_string method
                call_to_string = kind.expr.call_method("to_string", [])
                expression.kind = call_to_string.kind
            else:
                raise ValueError(
                    f"Cannot transform to-string for {ast.str_ty(kind.expr.ty)}"
                )
        elif isinstance(kind, ast.ArrayIndex):
            if kind.base.ty.has_field("get"):
                # If it quacks lite an get/set... it must be an get/set interface!
                assert len(kind.indici) == 1
                index = kind.indici[0]
                args = [ast.LabeledExpression("index", index, index.location)]
                call_get = kind.base.call_method("get", args)
                expression.kind = call_get.kind

    def get_rt_function(self, name: str):
        return self._rt_module.get_field(name)


def rewrite_enums(id_context: ast.IdContext, modules: list[ast.Module]):
    phase1 = EnumRewriterPhase1(id_context)
    phase1.transform(modules)
    enum_impls = phase1._enum_impls
    EnumRewriterPhase2(id_context, enum_impls).transform(modules)
    EnumRewriterPhase3(id_context, enum_impls).transform(modules)


@dataclass
class EnumImpl:
    struct_def: ast.StructDef


class EnumRewriterPhase1(BaseTransformer):
    """Create tagged union types"""

    name = "enum-rewrite-phase1"

    def __init__(self, id_context: ast.IdContext):
        super().__init__(id_context)
        self._enum_impls: dict[int, EnumImpl] = {}

    def visit_module(self, module: ast.Module):
        self.new_defs = []
        for definition in module.definitions:
            if isinstance(definition, ast.EnumDef):
                self.rewrite_enum_def(definition)
            else:
                self.new_defs.append(definition)

        module.definitions = self.new_defs
        super().visit_module(module)

    def rewrite_enum_def(self, enum_def: ast.EnumDef):
        """Create tagged union types / definitions"""

        logger.debug(f"Creating tagged union for {enum_def.id}")

        builder2 = ast.StructBuilder(
            self.new_id(f"{enum_def.id.name}Data"), enum_def.location
        )
        builder2.set_is_union(True)
        type_vars2 = [
            builder2.add_type_parameter(self.new_id(tp.id.name), tp.location)
            for tp in enum_def.type_parameters
        ]
        m2 = dict(zip(enum_def.type_parameters, type_vars2))
        builder2.add_field("nodata", ast.int_type, enum_def.location)

        for variant in enum_def.variants:
            union_field_name = f"data_{variant.id.name}"
            if len(variant.payload) == 0:
                pass
            elif len(variant.payload) == 1:
                t3 = ast.subst(variant.payload[0], m2)
                builder2.add_field(union_field_name, t3, variant.location)
            else:
                assert len(variant.payload) > 1
                builder3 = ast.StructBuilder(
                    self.new_id(f"{enum_def.id.name}Data{variant.id.name}"),
                    variant.location,
                )
                type_parameter_refs3 = [
                    builder3.add_type_parameter(self.new_id(tp.id.name), tp.location)
                    for tp in enum_def.type_parameters
                ]

                m3 = dict(zip(enum_def.type_parameters, type_parameter_refs3))
                for nr, p in enumerate(variant.payload):
                    builder3.add_field(f"f_{nr}", ast.subst(p, m3), variant.location)
                struct_def3 = builder3.finish()
                self.new_defs.append(struct_def3)
                t3 = struct_def3.apply(type_vars2)
                builder2.add_field(union_field_name, t3, variant.location)

        union_def = builder2.finish()
        self.new_defs.append(union_def)

        builder1 = ast.StructBuilder(self.new_id(enum_def.id.name), enum_def.location)
        type_parameter_refs1 = [
            builder1.add_type_parameter(self.new_id(tp.id.name), tp.location)
            for tp in enum_def.type_parameters
        ]
        builder1.add_field("tag", ast.int_type, enum_def.location)
        builder1.add_field(
            "data", union_def.apply(type_parameter_refs1), enum_def.location
        )
        tagged_data_def = builder1.finish()
        self.new_defs.append(tagged_data_def)
        self._enum_impls[id(enum_def)] = EnumImpl(struct_def=tagged_data_def)


class EnumRewriterPhase2(BaseTransformer):
    name = "enum-rewrite-phase2"

    def __init__(self, id_context: ast.IdContext, enum_impls):
        super().__init__(id_context)
        self._enum_impls = enum_impls

    def visit_statement(self, statement: ast.Statement):
        """
        Rewrite case statement over an enum type.
        - Change case into switch statement over an integer tag.
        - Change arm variables into seperate let statements
        - Extract values from arm out of the data field
        """
        super().visit_statement(statement)
        kind = statement.kind

        if isinstance(kind, ast.CaseStatement):
            statement.kind = self.transform_case(kind, statement.location)

    def transform_case(
        self, kind: ast.CaseStatement, location: Location
    ) -> ast.CompoundStatement:
        assert kind.value.ty.is_enum()
        impl = self._enum_impls[id(kind.value.ty.kind.tycon)]

        # x = value
        x_var = self.new_variable("x", ast.undefined_type(), location)
        let_x = ast.let_statement(x_var, None, kind.value, location)

        arms = []
        for arm in kind.arms:
            variant_idx: int = arm.variant.index
            union_field_name = f"data_{arm.variant.id.name}"
            # assign variables:
            body = []
            if len(arm.variables) == 0:
                pass
            elif len(arm.variables) == 1:
                union_val = x_var.ref_expr(arm.location).get_attr("data")
                data_val = union_val.get_attr(union_field_name)
                let_v = ast.let_statement(
                    arm.variables[0], None, data_val, arm.location
                )
                body.append(let_v)
            else:
                for var_idx, var in enumerate(arm.variables):
                    union_val = x_var.ref_expr(arm.location).get_attr("data")
                    struct_val = union_val.get_attr(union_field_name)
                    value = struct_val.get_attr(f"f_{var_idx}")
                    let_v = ast.let_statement(var, None, value, arm.location)
                    body.append(let_v)
            body.append(arm.block.body)
            body = ast.compound_statement(body, arm.location)
            block = ast.ScopedBlock(body)
            tag_val = ast.numeric_constant(variant_idx, arm.location)
            arms.append(ast.SwitchArm(tag_val, block, arm.location))

        if kind.else_clause:
            default_body = kind.else_clause
        else:
            default_body = ast.ScopedBlock(ast.unreachable_statement(location))

        # switch x.tag
        switch_1 = ast.switch_statement(
            x_var.ref_expr(location).get_attr("tag"),
            arms,
            default_body,
            location,
        )
        return ast.CompoundStatement([let_x, switch_1])

    def visit_expression(self, expression: ast.Expression):
        """Rewrite enum literal into tagged union"""
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, ast.EnumLiteral):
            expression.kind = self.rewrite_enum_literal(kind, expression.location)

    def rewrite_enum_literal(self, kind: ast.EnumLiteral, location: Location):
        assert kind.enum_ty.is_enum()
        impl = self._enum_impls[id(kind.enum_ty.kind.tycon)]
        tag_value = ast.numeric_constant(kind.variant.index, location)
        tagged_union_ty = impl.struct_def.apply(kind.enum_ty.kind.type_args)
        union_ty = tagged_union_ty.get_field_type("data")

        union_field_name = f"data_{kind.variant.id.name}"
        if len(kind.values) == 0:
            # Dummy value
            union_field_name = "nodata"
            value = ast.numeric_constant(0, location)
        elif len(kind.values) == 1:
            value = kind.values[0]
        else:
            assert len(kind.values) > 1
            struct_type = union_ty.get_field_type(union_field_name)
            value = ast.struct_literal(struct_type, kind.values, location)
        union_value = ast.union_literal(union_ty, union_field_name, value, location)
        return ast.StructLiteral(tagged_union_ty, [tag_value, union_value])


class EnumRewriterPhase3(BaseTransformer):
    name = "enum-rewrite-phase3"

    def __init__(self, id_context: ast.IdContext, enum_impls):
        super().__init__(id_context)
        self._enum_impls = enum_impls

    def change_enum_type(self, ty: ast.Type):
        # Change type into tagged union type
        assert ty.is_enum()
        enum_impl = self._enum_impls[id(ty.kind.tycon)]
        struct_def = enum_impl.struct_def
        ty.change_to(struct_def.apply(ty.kind.type_args))

    def visit_type(self, ty: ast.Type):
        super().visit_type(ty)
        if ty.is_enum():
            self.change_enum_type(ty)


def rewrite_classes(id_context, modules):
    ClassRewriter(id_context).transform(modules)


class ClassRewriter(BaseTransformer):
    name = "class-rewrite"

    def __init__(self, id_context: ast.IdContext):
        super().__init__(id_context)
        self._struct_defs = {}

    def visit_module(self, module: ast.Module):
        self.new_defs = []
        for definition in module.definitions:
            if isinstance(definition, ast.ClassDef):
                self.rewrite_class_def(definition)
            else:
                self.new_defs.append(definition)

        module.definitions = self.new_defs
        super().visit_module(module)

    def rewrite_class_def(self, class_def: ast.ClassDef):
        # Create a struct instead of a class:
        methods = []
        type_args = []
        builder = ast.StructBuilder(self.new_id(class_def.id.name), class_def.location)
        for type_parameter in class_def.type_parameters:
            type_arg = builder.add_type_parameter(
                self.new_id(type_parameter.id.name), type_parameter.location
            )
            type_args.append(type_arg)
        m = dict(zip(class_def.type_parameters, type_args))
        for member in class_def.members:
            if isinstance(member, ast.VarDef):
                ty = ast.subst(member.ty, m)
                builder.add_field(member.id.name, ty, member.location)
            elif isinstance(member, ast.FunctionDef):
                methods.append(member)
            else:
                raise NotImplementedError(str(member))

        struct_def = builder.finish()
        self.new_defs.append(struct_def)

        # Patch methods, add this parameter
        for method in methods:
            self.lift_method(method, class_def, struct_def)

        self.create_constructor(class_def, struct_def)

    def lift_method(
        self,
        method: ast.FunctionDef,
        class_def: ast.ClassDef,
        struct_def: ast.StructDef,
    ):
        logger.debug(f'lifting "{method.id}" to toplevel')
        method.id.name = f"{class_def.id.name}_{method.id.name}"

        type_args = []
        for tp in class_def.type_parameters:
            tp = ast.TypeParameter(self.new_id(tp.id.name), tp.location)
            # Hmm, append type arguments to already existing ones?
            # TBD: what happens with type annotations?
            method.type_parameters.append(tp)
            type_args.append(tp.get_ref())

        struct_type = struct_def.apply(type_args)
        this_param: ast.Parameter = method.this_parameter
        this_param.ty = struct_type
        assert this_param
        method.parameters.insert(0, this_param)

        m7 = dict(zip(class_def.type_parameters, type_args))
        replace_goo(method, m7)
        self.new_defs.append(method)

    def create_constructor(self, class_def: ast.ClassDef, struct_def: ast.StructDef):
        """Create constructor function"""
        type_parameters = []
        type_args = []
        for tp in class_def.type_parameters:
            tp = ast.TypeParameter(self.new_id(tp.id.name), tp.location)
            type_parameters.append(tp)
            type_args.append(tp.get_ref())
        struct_type = struct_def.apply(type_args)

        # Add parameters and init values
        m = dict(zip(class_def.type_parameters, type_args))
        ctor_parameters = []
        init_values = []
        for member in class_def.members:
            if isinstance(member, ast.VarDef):
                if member.value:
                    init_values.append(member.value)
                else:
                    # Create ctor parameter
                    new_id = self.new_id(member.id.name)
                    ty = ast.subst(member.ty, m)
                    ctor_parameter = ast.Parameter(new_id, True, ty, class_def.location)
                    ctor_parameters.append(ctor_parameter)
                    init_values.append(
                        ast.obj_ref(ctor_parameter, ty, class_def.location)
                    )
            elif isinstance(member, ast.FunctionDef):
                pass
            else:
                raise NotImplementedError(str(member))

        init_literal = ast.struct_literal(struct_type, init_values, class_def.location)
        ctor_code = ast.return_statement(init_literal, class_def.location)
        except_type = ast.void_type
        ctor_func = ast.function_def(
            self.new_id(f"{class_def.id.name}_ctor"),
            type_parameters,
            ctor_parameters,
            struct_type,
            except_type,
            ctor_code,
            class_def.location,
            Span.default(),
        )
        m7 = dict(zip(class_def.type_parameters, type_args))

        replace_goo(ctor_func, m7)
        self.new_defs.append(ctor_func)

        self._struct_defs[id(class_def)] = (struct_def, ctor_func)

    def visit_type(self, ty: ast.Type):
        super().visit_type(ty)
        if ty.is_class():
            # Change class type into tagged union type
            struct_def = self._struct_defs[id(ty.kind.tycon)][0]
            ty.change_to(struct_def.apply(ty.kind.type_args))

    def visit_expression(self, expression: ast.Expression):
        """Rewrite enum literal into tagged union"""
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, ast.ClassLiteral):
            assert expression.ty.is_class(), str(expression.ty)
            tycon = expression.ty.kind.tycon
            ctor_func = self._struct_defs[id(tycon)][1]
            ctor_call = ast.obj_ref(ctor_func, ast.void_type, expression.location).call(
                kind.arguments
            )
            expression.kind = ctor_call.kind
        elif isinstance(kind, ast.FunctionCall):
            if isinstance(kind.target.kind, ast.DotOperator):
                if kind.target.kind.base.ty.is_class():
                    # method call!
                    obj = kind.target.kind.base
                    method_func = kind.target.kind.base.ty.get_method(
                        kind.target.kind.field
                    )

                    # Insert
                    this_arg = ast.LabeledExpression("this2", obj, obj.location)
                    kind.args.insert(0, this_arg)
                    kind.target = ast.obj_ref(
                        method_func, ast.void_type, kind.target.location
                    )


def replace_goo(func_def: ast.FunctionDef, type_mapping):
    """Replace occurences of certain type variables and certain variables."""
    r = TypeReplacer(type_mapping)
    r.visit_definition(func_def)


class TypeReplacer(ast.AstVisitor):
    def __init__(self, type_mapping):
        super().__init__()
        self.type_mapping = type_mapping

    def visit_type(self, ty: ast.Type):
        super().visit_type(ty)
        if ty.is_type_parameter_ref():
            if ty.kind.type_parameter in self.type_mapping:
                t2 = self.type_mapping[ty.kind.type_parameter]
                ty.change_to(t2)


def rewrite_switch(id_context, modules):
    SwitchRewriter(id_context).transform(modules)


class SwitchRewriter(BaseTransformer):
    name = "switch-rewrite"

    def visit_statement(self, statement: ast.Statement):
        super().visit_statement(statement)
        kind = statement.kind

        if isinstance(kind, ast.SwitchStatement):
            logger.debug("rewrite switch into chain of if-then-else")
            # Step 1: capture switch value in variable:

            x_var = self.new_variable("x1234", kind.value.ty, statement.location)
            let_x = ast.let_statement(x_var, None, kind.value, statement.location)

            # Create if-then tree
            else_block = kind.default_block
            for arm in kind.arms:
                condition = x_var.ref_expr(arm.location).binop("==", arm.value)
                new_if = ast.if_statement(
                    condition, arm.block, else_block, arm.location
                )
                else_block = ast.ScopedBlock(new_if)

            statement.kind = ast.CompoundStatement([let_x, else_block.body])


def constant_folding(id_context, modules: list[ast.Module]):
    ConstantFolder(id_context).transform(modules)


class ConstantFolder(BaseTransformer):
    """Optimize constant expressions"""

    name = "constant-folder"

    def visit_statement(self, statement: ast.Statement):
        super().visit_statement(statement)
        kind = statement.kind

        if isinstance(kind, ast.IfStatement):
            if isinstance(kind.condition.kind, ast.BoolLiteral):
                # Deal with if-true or if-false
                if kind.condition.kind.value:
                    statement.kind = kind.true_block.body.kind
                else:
                    statement.kind = kind.false_block.body.kind

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, ast.Binop):
            if (
                isinstance(kind.lhs.kind, ast.NumericConstant)
                and isinstance(kind.rhs.kind, ast.NumericConstant)
                and kind.op in binops
            ):
                if expression.ty.is_int():
                    lhs = expr_eval_int(kind.lhs)
                    rhs = expr_eval_int(kind.rhs)
                    val = binops[kind.op](lhs, rhs)
                    expression.kind = ast.NumericConstant(val)
                elif expression.ty.is_bool() and kind.lhs.ty.is_int():
                    lhs = expr_eval_int(kind.lhs)
                    rhs = expr_eval_int(kind.rhs)
                    val = binops[kind.op](lhs, rhs)
                    assert isinstance(val, bool)
                    expression.kind = ast.BoolLiteral(val)


def expr_eval_int(expr: ast.Expression):
    kind = expr.kind
    if isinstance(kind, ast.NumericConstant):
        if isinstance(kind.value, int):
            return kind.value
        else:
            raise ValueError("No integer constant!")
    else:
        raise ValueError("No constant!")


binops = {
    "+": lambda x, y: x + y,
    "-": lambda x, y: x - y,
    "<": lambda x, y: x < y,
    ">": lambda x, y: x > y,
    "<=": lambda x, y: x <= y,
    ">=": lambda x, y: x >= y,
    "==": lambda x, y: x == y,
}


def replace_unions(id_context, modules: list[ast.Module]):
    UnionEraser(id_context).transform(modules)


class UnionEraser(BaseTransformer):
    """Replace union literals with a boxing operator."""

    name = "union-eraser"

    def visit_module(self, module: ast.Module):
        new_defs = []
        for definition in module.definitions:
            if isinstance(definition, ast.StructDef) and definition.is_union:
                pass
            else:
                new_defs.append(definition)

        module.definitions = new_defs
        super().visit_module(module)

    def visit_type(self, ty: ast.Type):
        super().visit_type(ty)
        if ty.is_union():
            ty.change_to(ast.ptr_type)

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, ast.UnionLiteral):
            expression.kind = ast.Box(kind.value)
        elif isinstance(kind, ast.DotOperator):
            if kind.base.ty.is_union():
                to_ty = expression.ty
                expression.kind = ast.Unbox(kind.base, to_ty)
