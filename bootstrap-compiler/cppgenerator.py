"""
Idea: Use C++ as intermediate code for bootstrapping.

Idea2: Use python code as bootstrapping target?

"""

from . import ast, types


def gencode(mod: ast.Module, output):
    g = Generator()
    for definition in mod.definitions:
        if isinstance(definition, ast.FunctionDef):
            g.gen_func_def(definition)
        else:
            pass


class Generator:
    def __init__(self):
        self.level = 0

    def gen_func_def(self, func_def: ast.FunctionDef):
        # TODO: return type
        parameters = [
            f'{self.gen_type(p.ty)} {p.name}' for p in func_def.parameters]
        self.print(f"void {func_def.name}({', '.join(parameters)}) {{")
        self.gen_block(func_def.statements)
        self.print(f"}}")
        self.print(f"")

    def gen_type(self, ty: types.MyType) -> str:
        if isinstance(ty, types.BaseType):
            return ty.name
        elif isinstance(ty, types.ArrayType):
            return f"{self.gen_type(ty.element_type)}[{ty.size}]"
        elif isinstance(ty, types.StructType):
            # return f"struct {ty.name}"
            return f"struct abc"
        else:
            return str(ty)

    def gen_block(self, block: list[ast.Statement]):
        self.indent()
        for statement in block:
            self.gen_statement(statement)
        self.dedent()

    def gen_statement(self, statement: ast.Statement):
        if isinstance(statement, ast.Expression):
            self.print(self.gen_expr(statement))
        elif isinstance(statement, ast.Let):
            # ty = 'int'  # TODO
            ty = self.gen_type(statement.ty)
            value = self.gen_expr(statement.value, parens=False)
            self.print(
                f"{ty} {statement.target} = {value};")
        elif isinstance(statement, ast.Assignment):
            self.print(
                f"{self.gen_expr(statement.target)} = {self.gen_expr(statement.value, parens=False)};")
        elif isinstance(statement, ast.IfStatement):
            self.print(
                f"if ({self.gen_expr(statement.condition, parens=False)}) {{")
            # if statement.true_statement:
            self.gen_block(statement.true_statement)
            if statement.false_statement:
                self.print(f"}} else {{")
                self.gen_block(statement.false_statement)
            self.print(f"}}")
        elif isinstance(statement, ast.While):
            self.print(
                f"while ({self.gen_expr(statement.condition, parens=False)}) {{")
            self.gen_block(statement.inner)
            self.print(f"}}")
        elif isinstance(statement, ast.ForStatement):
            # TODO!
            self.print(
                f"for (int {statement.target} = 1;111) {{")
            self.gen_block(statement.inner)
            self.print(f"}}")
        elif isinstance(statement, ast.Loop):
            self.print(f"while (true) {{")
            self.gen_block(statement.inner)
            self.print(f"}}")
        elif isinstance(statement, ast.Break):
            self.print(f"break;")
        elif isinstance(statement, ast.Continue):
            self.print(f"continue;")
        elif isinstance(statement, ast.Return):
            if statement.value:
                self.print(f"return {self.gen_expr(statement.value)};")
            else:
                self.print(f"return;")
        else:
            self.print(f"{statement}")

    def gen_expr(self, expr: ast.Expression, parens: bool = True):
        if isinstance(expr, ast.FunctionCall):
            args = ", ".join([self.gen_expr(arg, parens=False)
                             for arg in expr.args])
            return f"{self.gen_expr(expr.target)}({args})"
        elif isinstance(expr, ast.ArrayIndex):
            return f"{self.gen_expr(expr.base)}[{self.gen_expr(expr.index)}]"
        elif isinstance(expr, ast.DotOperator):
            return f"{self.gen_expr(expr.base)}.{expr.field}"
        elif isinstance(expr, ast.Binop):
            ops = {
                'and': '&&', 'or': '||'
            }
            op: str = ops.get(expr.op, expr.op)
            x = f"{self.gen_expr(expr.lhs)} {op} {self.gen_expr(expr.rhs)}"
            return f"({x})" if parens else x
        elif isinstance(expr, ast.NumericConstant):
            return f"{expr.value}"
        elif isinstance(expr, ast.StringConstant):
            return f"{expr.text}"
        elif isinstance(expr, ast.ArrayLiteral):
            values = [self.gen_expr(e) for e in expr.values]
            return f"[{', '.join(values)}]"
        elif isinstance(expr, ast.Parameter):
            return f"{expr.name}"
        elif isinstance(expr, ast.FunctionDef):
            return f"{expr.name}"
        elif isinstance(expr, ast.NameRef):
            return f"{expr.name}"
        elif isinstance(expr, ast.Variable):
            return f"{expr.name}"
        elif isinstance(expr, ast.BuiltinFunction):
            return f"{expr.name}"
        else:
            return str(expr)

    def indent(self):
        self.level += 1

    def dedent(self):
        self.level -= 1

    def print(self, txt: str):
        print("    " * self.level + txt)
