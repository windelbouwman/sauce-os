""" Generate python code

Idea: Use python code as bootstrapping target!

"""

import logging

from . import ast

logger = logging.getLogger("py-gencode")


def gen_pycode(modules: list[ast.Module], f):
    """Spit out python runable code"""
    logger.info("Generating python code")
    g = PyCodeGenerator(f)

    g.gen_header()
    for module in modules:
        for definition in module.definitions:
            g.gen_definition(definition)

    g.emit("main()")


class PyCodeGenerator:
    def __init__(self, f):
        self._level = 0
        self._f = f

    def gen_header(self):
        self.emit("# Autogenerated python code!")
        self.emit("# Make sure to provide functions such as 'std_print' etc..")
        self.emit("")

    def gen_definition(self, definition: ast.Definition):
        if isinstance(definition, ast.FunctionDef):
            self.gen_func(definition)
        elif isinstance(definition, ast.StructDef):
            if definition.is_union:
                self.emit(f"class {definition.name}:")
                self.indent()
                self.emit(f"def __init__(self, field, value):")
                self.indent()
                self.emit(f"setattr(self, field, value)")
                self.dedent()
                self.dedent()
            else:
                self.emit(f"class {definition.name}:")
                self.indent()
                field_names = [f"f_{field.name}" for field in definition.fields]
                args = ", ".join(field_names)
                self.emit(f"def __init__(self, {args}):")
                self.indent()
                for field_name in field_names:
                    self.emit(f"self.{field_name} = {field_name}")
                self.dedent()
                self.dedent()
        else:
            raise NotImplementedError(str(definition))
        self.emit("")

    def gen_func(self, func_def: ast.FunctionDef):
        if func_def.parameters:
            params = ", ".join([p.name for p in func_def.parameters])
        else:
            params = ""
        self.emit(f"def {func_def.name}({params}):")
        self.indent()
        self.gen_statement(func_def.statements)
        self.dedent()
        self.emit("")

    def gen_statement(self, statement: ast.Statement):
        kind = statement.kind
        if isinstance(kind, ast.LetStatement):
            val = self.gen_expression(kind.value)
            self.emit(f"{kind.variable.name} = {val}")
        elif isinstance(kind, ast.CompoundStatement):
            for statement in kind.statements:
                self.gen_statement(statement)
        elif isinstance(kind, ast.IfStatement):
            val = self.gen_expression(kind.condition, parens=False)
            self.emit(f"if {val}:")
            self.indent()
            self.gen_statement(kind.true_statement)
            self.dedent()
            self.emit("else:")
            self.indent()
            self.gen_statement(kind.false_statement)
            self.dedent()
        elif isinstance(kind, ast.SwitchStatement):
            value = self.gen_expression(kind.value)
            # TODO: unique name:
            tmp_var = "_x1337b"
            self.emit(f"{tmp_var} = {value}")
            self.emit("if False:")
            self.indent()
            self.emit("pass")
            self.dedent()
            for arm in kind.arms:
                v2 = self.gen_expression(arm.value)
                self.emit(f"elif {tmp_var} == {v2}:")
                self.indent()
                self.gen_statement(arm.body)
                self.dedent()
            self.emit("else:")
            self.indent()
            self.gen_statement(kind.default_body)
            self.dedent()

        elif isinstance(kind, ast.WhileStatement):
            val = self.gen_expression(kind.condition, parens=False)
            self.emit(f"while {val}:")
            self.indent()
            self.gen_statement(kind.inner)
            self.dedent()
        elif isinstance(kind, ast.BreakStatement):
            self.emit("break")
        elif isinstance(kind, ast.ContinueStatement):
            self.emit("continue")
        elif isinstance(kind, ast.PassStatement):
            self.emit("pass")
        elif isinstance(kind, ast.AssignmentStatement):
            target = self.gen_expression(kind.target)
            val = self.gen_expression(kind.value)
            op = kind.op
            self.emit(f"{target} {op} {val}")
        elif isinstance(kind, ast.ExpressionStatement):
            self.emit(self.gen_expression(kind.value))
        elif isinstance(kind, ast.ReturnStatement):
            if kind.value:
                self.emit(f"return {self.gen_expression(kind.value, parens=False)}")
            else:
                self.emit(f"return")
        else:
            raise NotImplementedError(str(kind))

    def gen_expression(self, expression: ast.Expression, parens: bool = True) -> str:
        kind = expression.kind
        if isinstance(kind, ast.StringConstant):
            return f'"{kind.text}"'
        elif isinstance(kind, ast.NumericConstant):
            return f"{kind.value}"
        elif isinstance(kind, ast.BoolLiteral):
            return f"{kind.value}"
        elif isinstance(kind, ast.ArrayLiteral):
            values = ", ".join([self.gen_expression(e) for e in kind.values])
            return f"[{values}]"
        elif isinstance(kind, ast.ArrayIndex):
            assert len(kind.indici) == 1
            base = self.gen_expression(kind.base)
            index = self.gen_expression(kind.indici[0])
            return f"{base}[{index}]"
        elif isinstance(kind, ast.DotOperator):
            base = self.gen_expression(kind.base)
            return f"{base}.f_{kind.field}"
        elif isinstance(kind, ast.StructLiteral):
            values = ", ".join(
                [self.gen_expression(e, parens=False) for e in kind.values]
            )
            return f"{kind.ty.kind.tycon.name}({values})"
        elif isinstance(kind, ast.UnionLiteral):
            name: str = kind.ty.kind.tycon.name
            value = self.gen_expression(kind.value)
            return f"{name}('f_{kind.field}', {value})"
        elif isinstance(kind, ast.Binop):
            lhs = self.gen_expression(kind.lhs)
            rhs = self.gen_expression(kind.rhs)
            res = f"{lhs} {kind.op} {rhs}"
            return f"({res})" if parens else res
        elif isinstance(kind, ast.Unop):
            rhs = self.gen_expression(kind.rhs)
            res = f"{kind.op} {rhs}"
            return f"({res})" if parens else res
        elif isinstance(kind, ast.ObjRef):
            obj = kind.obj
            if isinstance(obj, (ast.Variable, ast.FunctionDef)):
                return obj.name
            elif isinstance(obj, ast.BuiltinFunction):
                return obj.name
            elif isinstance(obj, ast.Parameter):
                return obj.name
            else:
                raise NotImplementedError(str(obj))
        elif isinstance(kind, ast.TypeCast):
            # TODO!
            return self.gen_expression(kind.value)
        elif isinstance(kind, ast.FunctionCall):
            callee = self.gen_expression(kind.target)
            args = ", ".join([self.gen_expression(a, parens=False) for a in kind.args])
            return f"{callee}({args})"
        else:
            raise NotImplementedError(str(kind))

    def indent(self):
        self._level += 1

    def dedent(self):
        self._level -= 1

    def emit(self, txt: str):
        indent = self._level * "    "
        print(indent + txt, file=self._f)
