"""Type checker."""

import logging

from . import ast
from .basepass import BasePass
from .location import Location

logger = logging.getLogger("typechecker")


class TypeChecker(BasePass):
    def __init__(self):
        super().__init__()
        self._function = None
        self._except_handlers = []

    def check_module(self, module: ast.Module):
        self.begin(module.filename, f"Type checking module '{module.name}'")
        self.visit_module(module)
        self.finish("Type check OK.")

    def visit_definition(self, definition: ast.Definition):
        self._was_error = False

        if isinstance(definition, ast.FunctionDef):
            logger.debug(f"Checking function '{definition.id}'")
            assert not self._function
            self._function = definition
            may_raise = not definition.except_type.is_void()
            if may_raise:
                self._except_handlers.append(definition.except_type)
            super().visit_definition(definition)
            if not definition.statement.ty.is_unreachable():
                self.assert_statement_type(definition.statement, definition.return_ty)
            if may_raise:
                self._except_handlers.pop(-1)
            self._function = None
        else:
            super().visit_definition(definition)

            if isinstance(definition, (ast.StructDef, ast.EnumDef, ast.TypeDef)):
                pass
            elif isinstance(definition, (ast.ClassDef, ast.ExternFunction)):
                pass
            elif isinstance(definition, ast.VarDef):
                if definition.value:
                    self.coerce(definition.value, definition.ty)
            else:
                raise NotImplementedError(str(definition))

    def visit_statement(self, statement: ast.Statement):
        if self._was_error:
            return

        kind = statement.kind

        # Handle special cases:
        if isinstance(kind, ast.CaseStatement):
            self.visit_expression(kind.value)
            if kind.value.ty.is_enum():
                variant_names = kind.value.ty.get_variant_names()
                for arm in kind.arms:
                    if kind.value.ty.has_variant(arm.name):
                        variant_names.remove(arm.name)
                        variant = kind.value.ty.get_variant(arm.name)
                        payload_types = kind.value.ty.get_variant_types(arm.name)

                        # HACK to pass variant to transform pass:
                        arm.variant = variant

                        if len(payload_types) == len(arm.variables):
                            for v, t in zip(arm.variables, payload_types):
                                v.ty = t
                        else:
                            self.error(
                                arm.location,
                                f"Expected {len(payload_types)} variables, got {len(arm.variables)}",
                            )
                        # TODO: check missing fields
                    else:
                        self.error(arm.location, f"No enum variant {arm.name}")
                if variant_names and not kind.else_clause:
                    self.error(statement.location, f"Cases {variant_names} not covered")
            else:
                self.error(kind.value.location, f"Expected enum, not {kind.value.ty}")

            ty = ast.unreachable_type()
            for arm in kind.arms:
                self.visit_node(arm)
                ty = self.merge_paths(arm.block.body, ty)

            if kind.else_clause:
                self.visit_statement(kind.else_clause.body)
                ty = self.merge_paths(kind.else_clause.body, ty)

            statement.ty = ty

        elif isinstance(kind, ast.ForStatement):
            self.visit_expression(kind.values)
            if kind.values.ty.is_array():
                kind.variable.ty = kind.values.ty.kind.element_type
            elif kind.values.ty.is_iterable_like():
                # If it quacks lite an iterator... it must be an iterator!
                iter_ty: ast.Type = kind.values.ty.get_field_type(
                    "iter"
                ).kind.return_type
                opt_ty: ast.Type = iter_ty.get_field_type("next").kind.return_type
                val_ty = opt_ty.get_variant_types("Some")[0]
                kind.variable.ty = val_ty
            elif kind.values.ty.is_sequence_like():
                val_ty: ast.Type = kind.values.ty.get_field_type("get").kind.return_type
                kind.variable.ty = val_ty
            else:
                self.error(
                    kind.values.location,
                    f"Expected array, iterable or sequence. Got {kind.values.ty}",
                )
            self.visit_statement(kind.block.body)
            statement.ty = ast.void_type
        elif isinstance(kind, ast.TryStatement):
            self._except_handlers.append(kind.parameter.ty)
            self.visit_statement(kind.try_block.body)
            self._except_handlers.pop()
            self.visit_statement(kind.except_block.body)
            statement.ty = ast.void_type
        else:
            super().visit_statement(statement)

            if self._was_error:
                return

            if isinstance(kind, ast.LoopStatement):
                self.assert_void(kind.block.body)
                statement.ty = ast.void_type
            elif isinstance(kind, ast.WhileStatement):
                self.coerce(kind.condition, ast.bool_type)
                self.assert_void(kind.block.body)
                statement.ty = ast.void_type
            elif isinstance(kind, ast.IfStatement):
                self.coerce(kind.condition, ast.bool_type)
                ty = self.merge_paths(kind.false_block.body, kind.true_block.body.ty)
                statement.ty = ty
            elif isinstance(kind, ast.SwitchStatement):
                self.coerce(kind.value, ast.int_type)
                ty = kind.default_block.body.ty
                for arm in kind.arms:
                    ty = self.merge_paths(arm.block.body, ty)
                statement.ty = ty
            elif isinstance(kind, ast.ExpressionStatement):
                # Check void type: Good idea?
                statement.ty = kind.value.ty
            elif isinstance(kind, (ast.BreakStatement, ast.ContinueStatement)):
                # TODO!
                statement.ty = ast.void_type
            elif isinstance(kind, ast.PassStatement):
                statement.ty = ast.void_type
            elif isinstance(kind, ast.UnreachableStatement):
                statement.ty = ast.unreachable_type()
            elif isinstance(kind, ast.CompoundStatement):
                for x in kind.statements[:-1]:
                    self.assert_void(x)
                statement.ty = kind.statements[-1].ty
            elif isinstance(kind, ast.ReturnStatement):
                if kind.value:
                    if not self.unify(kind.value.ty, self._function.return_ty):
                        self.error(
                            kind.value.location,
                            f"Expected {ast.str_ty(self._function.return_ty)}, got {ast.str_ty(kind.value.ty)}",
                        )
                statement.ty = ast.unreachable_type()
            elif isinstance(kind, ast.RaiseStatement):
                self.check_may_raise(kind.value.ty, statement.location)
                statement.ty = ast.unreachable_type()
            elif isinstance(kind, ast.LetStatement):
                if kind.ty:
                    self.coerce(kind.value, kind.ty)
                    kind.variable.ty = kind.ty
                else:
                    kind.variable.ty = kind.value.ty.clone()
                statement.ty = ast.void_type
            elif isinstance(kind, ast.AssignmentStatement):
                self.coerce(kind.value, kind.target.ty)
                statement.ty = ast.void_type
            else:
                raise NotImplementedError(str(statement))

    def visit_expression(self, expression: ast.Expression):
        """Perform type checking on expression!"""
        super().visit_expression(expression)

        if self._was_error:
            return

        kind = expression.kind
        if isinstance(
            kind,
            (
                ast.NumericConstant,
                ast.StringConstant,
                ast.CharConstant,
                ast.BoolLiteral,
            ),
        ):
            pass
        elif isinstance(kind, ast.ArrayLiteral):
            assert len(kind.values) > 0
            expression.ty = ast.array_type(len(kind.values), kind.values[0].ty)
        elif isinstance(kind, ast.ArrayLiteral2):
            expression.ty = ast.array_type(None, kind.ty)
            self.coerce(kind.size, ast.int_type)
        elif isinstance(kind, ast.Binop):
            # Introduce some heuristics...
            if kind.lhs.ty.is_int() and kind.rhs.ty.is_float():
                ty = kind.rhs.ty
            else:
                ty = kind.lhs.ty

            self.coerce(kind.lhs, ty)
            self.coerce(kind.rhs, ty)

            if kind.op in ["<", ">", "<=", ">=", "==", "!="]:
                expression.ty = ast.bool_type
            elif kind.op in ["and", "or"]:
                self.coerce(kind.lhs, ast.bool_type)
                self.coerce(kind.rhs, ast.bool_type)
                expression.ty = ast.bool_type
            else:
                expression.ty = ty

        elif isinstance(kind, ast.Unop):
            if kind.op == "not":
                self.coerce(kind.rhs, ast.bool_type)
                expression.ty = ast.bool_type
            elif kind.op == "-":
                # TODO: Assert numeric type?
                # elif kind.lhs.ty.is_int() and kind.rhs.ty.is_float():
                expression.ty = kind.rhs.ty
            else:
                raise NotImplementedError(kind.op)

        elif isinstance(kind, ast.DotOperator):
            if kind.base.ty.has_field(kind.field):
                expression.ty = kind.base.ty.get_field_type(kind.field)
            else:
                self.error(
                    expression.location,
                    f"{ast.str_ty(kind.base.ty)} has no field '{kind.field}'",
                )
                expression.ty = ast.void_type

        elif isinstance(kind, ast.ArrayIndex):
            if isinstance(kind.base.ty.kind, ast.ArrayType):
                expression.ty = kind.base.ty.kind.element_type
            elif kind.base.ty.has_field("get"):
                # If it quacks lite an get/set... it must be an get/set interface!
                val_ty: ast.Type = kind.base.ty.get_field_type("get").kind.return_type
                expression.ty = val_ty
            else:
                self.error(
                    expression.location,
                    f"Indexing requires array type, not {ast.str_ty(kind.base.ty)}",
                )

            if len(kind.indici) == 1:
                self.coerce(kind.indici[0], ast.int_type)
            else:
                self.error(
                    expression.location,
                    "Array indexing only work with 1 integer index.",
                )

        elif isinstance(kind, ast.FunctionCall):
            if isinstance(kind.target.ty.kind, ast.FunctionType):
                ftyp = kind.target.ty.kind
                arg_types = ftyp.parameter_types
                return_type = ftyp.return_type
                values = [a.value for a in kind.args]
                self.check_arguments(arg_types, values, expression.location)
                expression.ty = return_type

                # Check argument names:
                if len(ftyp.parameter_names) == len(values):
                    for expected_name, arg in zip(ftyp.parameter_names, kind.args):
                        if expected_name:
                            if arg.name:
                                if expected_name != arg.name:
                                    self.error(
                                        arg.location,
                                        f"Expected labeled argument '{expected_name}', got '{arg.name}'",
                                    )
                            else:
                                self.error(
                                    arg.location,
                                    f"Expected labeled argument '{expected_name}'",
                                )
                        # TODO: check for redundant labels?
                        # else:
                        #     if got_name:
                        #         self.error(
                        #             expression.location,
                        #             f"Unexpected label: {got_name}",
                        #         )

                # Check if we may call error throwing function
                if not ftyp.except_type.is_void():
                    self.check_may_raise(ftyp.except_type, expression.location)
            elif kind.target.ty.is_class():
                # Assume constructor is called without arguments for now
                # TODO: allow constructors!
                self.check_arguments([], kind.args, expression.location)
                expression.ty = kind.target.ty
            else:
                self.error(
                    expression.location,
                    f"Trying to call non-function type: {ast.str_ty(kind.target.ty)}",
                )

        elif isinstance(kind, ast.NameRef):
            raise ValueError(f"Must be resolved: {kind}")
        elif isinstance(kind, ast.StructLiteral):
            field_types = kind.ty.get_field_types()
            assert len(field_types) == len(kind.values)
            for field_type, value in zip(field_types, kind.values):
                self.coerce(value, field_type)
            expression.ty = kind.ty
        elif isinstance(kind, ast.UnionLiteral):
            field_type = kind.ty.get_field_type(kind.field)
            self.coerce(kind.value, field_type)
            expression.ty = kind.ty
        elif isinstance(kind, ast.EnumLiteral):
            payload_types = kind.enum_ty.get_variant_types(kind.variant.id.name)
            self.check_arguments(payload_types, kind.values, expression.location)
            expression.ty = kind.enum_ty.clone()
        elif isinstance(kind, ast.ClassLiteral):
            expression.ty = kind.class_ty.clone()
        elif isinstance(kind, ast.TypeLiteral):
            self.error(expression.location, "Unexpected type")
        elif isinstance(kind, ast.GenericLiteral):
            self.error(expression.location, "Unexpected generic")
        elif isinstance(kind, ast.SemiEnumLiteral):
            self.error(expression.location, "Unexpected enum variant constructor")
        elif isinstance(kind, ast.ObjRef):
            obj = kind.obj
            if isinstance(obj, ast.Variable):
                expression.ty = obj.ty.clone()
            elif isinstance(obj, ast.VarDef):
                expression.ty = obj.ty.clone()
            elif isinstance(obj, ast.ExternFunction):
                expression.ty = obj.ty
            elif isinstance(obj, ast.FunctionDef):
                expression.ty = obj.get_type()
            elif isinstance(obj, ast.Parameter):
                expression.ty = obj.ty.clone()
            elif isinstance(obj, ast.ClassDef):
                # Arg, type arguments?
                expression.ty = obj.get_type([])
            else:
                raise NotImplementedError(str(kind))
        elif isinstance(kind, ast.TypeCast):
            expression.ty = kind.ty
        elif isinstance(kind, ast.ToString):
            if kind.expr.ty.is_int() or kind.expr.ty.is_char():
                pass
            elif kind.expr.ty.has_field("to_string"):
                pass
            else:
                self.coerce(kind.expr, ast.str_type)
            expression.ty = ast.str_type
        elif isinstance(kind, ast.Box):
            expression.ty = ast.ptr_type
        elif isinstance(kind, ast.Unbox):
            expression.ty = kind.to_type
        elif isinstance(kind, ast.StatementExpression):
            expression.ty = kind.statement.ty
        else:
            raise NotImplementedError(str(expression.kind))

    def check_may_raise(self, exc_type: ast.Type, location: Location):
        if self._except_handlers:
            expected_exc_type = self._except_handlers[-1]
            if not self.unify(exc_type, expected_exc_type):
                self.error(
                    location,
                    f"Raises {ast.str_ty(exc_type)}, but can only raise {ast.str_ty(expected_exc_type)}",
                )

        else:
            self.error(location, "Cannot raise exception here")

    def check_arguments(
        self, types: list[ast.Type], values: list[ast.Expression], location: Location
    ):
        """Check amount and types a list of values"""
        if len(values) == len(types):
            for arg, expected_ty in zip(values, types):
                self.coerce(arg, expected_ty)
        else:
            self.error(location, f"Got {len(values)} arguments, expected {len(types)}")

    def assert_void(self, statement: ast.Statement):
        if not statement.ty.is_unreachable():
            self.check_type(statement.ty, ast.void_type, statement.location)

    def assert_statement_type(self, statement: ast.Statement, ty: ast.Type):
        self.check_type(statement.ty, ty, statement.location)

    def merge_paths(self, statement: ast.Statement, ty: ast.Type) -> ast.Type:
        if ty.is_unreachable():
            return statement.ty
        elif statement.ty.is_unreachable():
            return ty
        else:
            self.check_type(statement.ty, ty, statement.location)
            return ty

    def coerce(self, expression: ast.Expression, ty: ast.Type):
        """Check if expression is of given type, raise error otherwise."""
        if not isinstance(expression, ast.Expression):
            raise TypeError(f"{expression} must be an ast.Expression")

        # Try to auto-convert before check:
        if expression.ty.is_int() and ty.is_float():
            # Auto-conv int to floats
            old_expr = expression.clone()
            expression.kind = ast.TypeCast(ty, old_expr)
            expression.ty = ty

        self.check_type(expression.ty, ty, expression.location)

    def check_type(self, given_ty: ast.Type, expected_ty: ast.Type, location: Location):
        if not self.unify(given_ty, expected_ty):
            self.error(
                location,
                f"Expected {ast.str_ty(expected_ty)}, got {ast.str_ty(given_ty)}",
            )

    def unify(self, a: ast.Type, b: ast.Type) -> bool:
        """Unify types a and b."""
        if isinstance(a.kind, ast.App) and isinstance(b.kind, ast.App):
            # Check equal tycon:
            if not a.kind.tycon.equals(b.kind.tycon):
                return False

            # Check equal type_args:
            return self.unify_many(a.kind.type_args, b.kind.type_args)
        elif isinstance(a.kind, ast.BaseType) and isinstance(b.kind, ast.BaseType):
            return a.kind.equals(b.kind)
        elif a.is_void() and b.is_void():
            return True
        elif isinstance(a.kind, ast.TypeParameterKind) and isinstance(
            b.kind, ast.TypeParameterKind
        ):
            return a.kind.type_parameter is b.kind.type_parameter
        elif isinstance(a.kind, ast.FunctionType) and isinstance(
            b.kind, ast.FunctionType
        ):
            if not self.unify(a.kind.return_type, b.kind.return_type):
                return False
            return self.unify_many(a.kind.parameter_types, b.kind.parameter_types)
        elif isinstance(a.kind, ast.ArrayType) and isinstance(b.kind, ast.ArrayType):
            return self.unify(a.kind.element_type, b.kind.element_type)
        elif isinstance(a.kind, ast.Meta):
            if a.kind.assigned:
                # Patch and recurse:
                a.change_to(a.kind.assigned)
                return self.unify(a, b)
            elif isinstance(b.kind, ast.Meta):
                return a.kind is b.kind
            elif (
                b.is_struct()
                or b.is_class()
                or b.is_type_parameter_ref()
                or b.is_void()
                or b.is_int()
                or b.is_bool()
                or b.is_str()
                or b.is_enum()
            ):
                # TODO: check if b contains meta-var
                # Assign type to meta-var:
                a.kind.assigned = b
                # Patch type:
                a.kind = b.kind
                return True
            else:
                raise NotImplementedError(str(a) + str(b))
                # if isinstance(b.kind, )
                return True
        elif isinstance(b.kind, ast.Meta):
            # Simply swap comparison
            return self.unify(b, a)
        elif a.is_unreachable() and b.is_unreachable():
            return True
        else:
            return False

    def unify_many(self, types1: list[ast.Type], types2: list[ast.Type]) -> bool:
        if len(types1) == len(types2):
            return all(self.unify(u, v) for u, v in zip(types1, types2))
        else:
            return False
